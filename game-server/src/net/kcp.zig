// https://github.com/iotalking/kcp_zig/blob/5f97b23e1354b0c540b5d4212929d8ddd3904c1f/src/zkcp.zig

const std = @import("std");
const builtin = @import("builtin");

pub const native_endian = builtin.cpu.arch.endian();

const IKCP_FASTACK_CONSERVE = true;
//=====================================================================
// KCP BASIC
//=====================================================================
const IKCP_RTO_NDL: u32 = 30; // no delay min rto
const IKCP_RTO_MIN: u32 = 100; // normal min rto
const IKCP_RTO_DEF: u32 = 200;
const IKCP_RTO_MAX: u32 = 60000;
const IKCP_CMD_PUSH: u32 = 81; // cmd: push data
const IKCP_CMD_ACK: u32 = 82; // cmd: ack
const IKCP_CMD_WASK: u32 = 83; // cmd: window probe (ask)
const IKCP_CMD_WINS: u32 = 84; // cmd: window size (tell)
const IKCP_ASK_SEND: u32 = 1; // need to send IKCP_CMD_WASK
const IKCP_ASK_TELL: u32 = 2; // need to send IKCP_CMD_WINS
const IKCP_WND_SND: u32 = 32;
const IKCP_WND_RCV: u32 = 128; // must >= max fragment size
const IKCP_MTU_DEF: u32 = 1400;
const IKCP_ACK_FAST: u32 = 3;
const IKCP_INTERVAL: u32 = 100;
pub const IKCP_OVERHEAD: u32 = 28;
const IKCP_DEADLINK: u32 = 20;
const IKCP_THRESH_INIT: u32 = 2;
const IKCP_THRESH_MIN: u32 = 2;
const IKCP_PROBE_INIT: u32 = 7000; // 7 secs to probe window size
const IKCP_PROBE_LIMIT: u32 = 120000; // up to 120 secs to probe window
const IKCP_FASTACK_LIMIT: u32 = 5; // max times to trigger fastack

pub const IKCP_LOG_OUT_OUTPUT: u32 = 1;
pub const IKCP_LOG_OUT_INPUT: u32 = 2;
pub const IKCP_LOG_OUT_SEND: u32 = 4;
pub const IKCP_LOG_OUT_RECV: u32 = 8;
pub const IKCP_LOG_OUT_IN_DATA: u32 = 16;
pub const IKCP_LOG_OUT_IN_ACK: u32 = 32;
pub const IKCP_LOG_OUT_IN_PROBE: u32 = 64;
pub const IKCP_LOG_OUT_IN_WINS: u32 = 128;
pub const IKCP_LOG_OUT_DATA: u32 = 256;
pub const IKCP_LOG_OUT_ACK: u32 = 512;
pub const IKCP_LOG_OUT_PROBE: u32 = 1024;
pub const IKCP_LOG_OUT_WINS: u32 = 2048;

//---------------------------------------------------------------------
// encode / decode
//---------------------------------------------------------------------

// /* encode 8 bits unsigned int */
inline fn ikcp_encode8u(p: [*]u8, c: u8) [*]u8 {
    const up: [*]u8 = @ptrCast(p);
    up[0] = c;
    return p + 1;
}

// /* decode 8 bits unsigned int */
inline fn ikcp_decode8u(p: [*]u8, c: *u8) [*]u8 {
    c.* = @intCast(p[0]);
    return p + 1;
}

// /* encode 16 bits unsigned int (lsb) */
inline fn ikcp_encode16u(p: [*]u8, w: u16) [*]u8 {
    std.mem.writeInt(u16, @ptrCast(p), w, native_endian);
    return p + 2;
}

// /* decode 16 bits unsigned int (lsb) */
inline fn ikcp_decode16u(p: [*]u8, w: *u16) [*]u8 {
    w.* = std.mem.readInt(u16, @ptrCast(p), native_endian);
    return p + 2;
}

// /* encode 32 bits unsigned int (lsb) */
inline fn ikcp_encode32u(p: [*]u8, l: u32) [*]u8 {
    std.mem.writeInt(u32, @ptrCast(p), l, native_endian);
    return p + 4;
}
// /* decode 32 bits unsigned int (lsb) */
inline fn ikcp_decode32u(p: [*]u8, l: *u32) [*]u8 {
    l.* = std.mem.readInt(u32, @ptrCast(p), native_endian);
    return p + 4;
}

test "ikcp test" {
    std.testing.log_level = .debug;
    const expect = std.testing.expect;
    var buffer = std.mem.zeroes([64]u8);
    var p = ikcp_encode8u(&buffer, 'a');
    var c: u8 = 0;
    p = ikcp_decode8u(&buffer, &c);
    try expect(c == 'a');
    _ = ikcp_encode16u(&buffer, 12);
    var c16: u16 = 0;
    _ = ikcp_decode16u(&buffer, &c16);
    try expect(c16 == 12);
    var c32: u32 = 0xf12;
    _ = ikcp_encode32u(&buffer, c32);
    _ = ikcp_decode32u(&buffer, &c32);
    try expect(c32 == 0xf12);

    const a: u32 = 1;
    const b: u32 = 2;
    try expect(_imax_(a, b) == 2);
    try expect(_imin_(a, b) == 1);
    try expect(_ibound_(3, 4, 5) == 4);

    var kcp: Kcp = try Kcp.init(std.testing.allocator, 1, 12);
    defer kcp.deinit();
    const seg = try Seg.init(kcp.allocator, 1024);
    // defer seg.deinit(kcp.allocator);
    std.debug.assert(@intFromPtr(seg) == @intFromPtr(&seg.node));

    var head = try LoopQueue.init(kcp.allocator);
    defer head.deinit(kcp.allocator);
    head.addTail(&seg.node);
    // seg.node.delSelf();

    kcp.logmask = IKCP_LOG_OUT_OUTPUT;
    kcp.outputFunc = test_output;
    kcp.writelogFunc = test_log;
    _ = kcp.output(@ptrCast(&buffer));
}
fn test_log(log: []const u8, kcp: *Kcp, user: ?usize) void {
    _ = kcp;
    _ = user;
    std.log.debug("{s}", .{log});
}
fn test_output(buf: []const u8, kcp: *Kcp, user: ?usize) usize {
    _ = kcp;
    _ = user;
    return buf.len;
}
inline fn _imin_(a: u32, b: u32) u32 {
    return if (a <= b) a else b;
}
inline fn _imax_(a: u32, b: u32) u32 {
    return if (a >= b) a else b;
}

inline fn _ibound_(lower: u32, middle: u32, upper: u32) u32 {
    return _imin_(_imax_(lower, middle), upper);
}

pub inline fn _itimediff(later: u32, earlier: u32) i32 {
    return @as(i32, @bitCast(later)) - @as(i32, @bitCast(earlier));
}

test "1itimediff" {
    const expect = std.testing.expect;
    const d = _itimediff(1, 2);
    try expect(d == -2);
}
//---------------------------------------------------------------------
// manage segment
//---------------------------------------------------------------------
const LoopQueue = struct {
    next: *LoopQueue,
    prev: *LoopQueue,
    mem: ?[]u8,
    pub fn init(allocator: std.mem.Allocator) !*LoopQueue {
        const mem = try allocator.alloc(u8, @sizeOf(LoopQueue));
        const self: *LoopQueue = @ptrCast(@alignCast(mem));
        self.mem = mem;
        self.prev = self;
        self.next = self;
        std.debug.assert(@intFromPtr(mem.ptr) == @intFromPtr(self));
        return self;
    }
    pub fn initSelf(self: *LoopQueue) void {
        self.prev = self;
        self.next = self;
    }
    pub fn deinit(self: *LoopQueue, allocator: std.mem.Allocator) void {
        var next = self.next;
        while (next != self) {
            const nextnext = next.next;
            next.delSelf();
            next.deinit(allocator);
            next = nextnext;
        }
        if (self.mem) |mem| {
            self.mem = null;
            allocator.free(mem);
        }
    }
    pub fn addHead(self: *LoopQueue, node: *LoopQueue) void {
        node.prev = self;
        node.next = self.next;
        self.next.prev = node;
        self.next = node;
    }
    pub fn addTail(self: *LoopQueue, node: *LoopQueue) void {
        node.prev = self.prev;
        node.next = self;
        self.prev.next = node;
        self.prev = node;
    }
    pub fn delSelf(self: *LoopQueue) void {
        self.next.prev = self.prev;
        self.prev.next = self.next;
        self.next = self;
        self.prev = self;
    }
    pub inline fn isEmpty(s: *LoopQueue) bool {
        return s == s.next;
    }
    pub fn getSeg(self: *LoopQueue) *Seg {
        const s: *Seg = @ptrCast(self);
        return s;
    }

    pub fn print(s: *LoopQueue) void {
        _ = s;
    }
};

const Seg = struct {
    node: LoopQueue,
    conv: u32 = 0,
    token: u32 = 0,
    cmd: u32 = 0,
    frg: u32 = 0,
    wnd: u32 = 0,
    ts: u32 = 0,
    sn: u32 = 0,
    una: u32 = 0,
    len: u32 = 0,
    resendts: u32 = 0,
    rto: u32 = 0,
    fastack: u32 = 0,
    xmit: u32 = 0,
    data: []u8,

    pub fn init(allocator: std.mem.Allocator, size: usize) !*Seg {
        const mem = try allocator.alloc(u8, @sizeOf(Seg) + size);
        const self: *Seg = @ptrCast(@alignCast(mem));
        self.* = .{
            .node = .{
                .mem = mem,
                .next = &self.node,
                .prev = &self.node,
            },
            .data = mem[@sizeOf(Seg)..],
        };
        return self;
    }
    pub fn deinit(self: *Seg, allocator: std.mem.Allocator) void {
        self.node.deinit(allocator);
    }

    //---------------------------------------------------------------------
    // ikcp_encode_seg
    //---------------------------------------------------------------------
    pub fn encode(seg: *const Seg, _ptr: [*]u8) [*]u8 {
        var ptr = @constCast(_ptr);
        ptr = ikcp_encode32u(ptr, seg.conv);
        ptr = ikcp_encode32u(ptr, seg.token);
        ptr = ikcp_encode8u(ptr, @truncate(seg.cmd));
        ptr = ikcp_encode8u(ptr, @truncate(seg.frg));
        ptr = ikcp_encode16u(ptr, @truncate(seg.wnd));
        ptr = ikcp_encode32u(ptr, seg.ts);
        ptr = ikcp_encode32u(ptr, seg.sn);
        ptr = ikcp_encode32u(ptr, seg.una);
        ptr = ikcp_encode32u(ptr, seg.len);
        return ptr;
    }
};

pub const OutputFunc = *const fn (buf: []const u8, convId: u32, user: ?usize) usize;
pub const WriteLogFunc = *const fn (log: []const u8, kcp: *Kcp, user: ?usize) void;
pub const Kcp = struct {
    conv: u32 = 0,
    token: u32 = 0,
    mtu: u32 = IKCP_MTU_DEF,
    mss: u32 = 0,
    state: u32 = 0,

    snd_una: u32 = 0,
    snd_nxt: u32 = 0,
    rcv_nxt: u32 = 0,
    ts_recent: u32 = 0,
    ts_lastack: u32 = 0,
    ssthresh: u32 = IKCP_THRESH_INIT,

    rx_rttval: i32 = 0,
    rx_srtt: i32 = 0,
    rx_rto: i32 = IKCP_RTO_DEF,
    rx_minrto: i32 = IKCP_RTO_MIN,

    snd_wnd: u32 = IKCP_WND_SND,
    rcv_wnd: u32 = IKCP_WND_RCV,
    rmt_wnd: u32 = IKCP_WND_RCV,
    cwnd: u32 = 0,
    probe: u32 = 0,
    current: u32 = 0,
    interval: u32 = IKCP_INTERVAL,
    ts_flush: u32 = IKCP_INTERVAL,
    xmit: u32 = 0,
    nrcv_buf: u32 = 0,
    nsnd_buf: u32 = 0,
    nrcv_que: u32 = 0,
    nsnd_que: u32 = 0,
    nodelay: u32 = 0,
    updated: u32 = 0,
    ts_probe: u32 = 0,
    probe_wait: u32 = 0,
    dead_link: u32 = IKCP_DEADLINK,
    incr: u32 = 0,
    snd_queue: *LoopQueue,
    rcv_queue: *LoopQueue,
    snd_buf: *LoopQueue,
    rcv_buf: *LoopQueue,
    acklist: ?[]u32 = null,
    ackcount: u32 = 0,
    ackblock: u32 = 0,
    user: ?usize = null,
    buffer: []u8,
    fastresend: usize = 0,
    fastlimit: usize = IKCP_FASTACK_LIMIT,
    nocwnd: usize = 0,
    stream: usize = 0,
    logmask: u32 = IKCP_LOG_OUT_OUTPUT,
    outputFunc: ?OutputFunc = null,
    writelogFunc: ?WriteLogFunc = null,

    allocator: std.mem.Allocator,
    pub fn init(allocator: std.mem.Allocator, conv: u32, token: u32, user: usize) !Kcp {
        const snd_queue = try LoopQueue.init(allocator);
        errdefer snd_queue.deinit(allocator);
        const rcv_queue = try LoopQueue.init(allocator);
        errdefer rcv_queue.deinit(allocator);
        const snd_buf = try LoopQueue.init(allocator);
        errdefer snd_buf.deinit(allocator);
        const rcv_buf = try LoopQueue.init(allocator);
        errdefer rcv_buf.deinit(allocator);
        const buffer = try allocator.alloc(u8, (IKCP_MTU_DEF + IKCP_OVERHEAD) * 3);
        errdefer allocator.free(buffer);
        var kcp = Kcp{
            .allocator = allocator,
            .snd_queue = snd_queue,
            .rcv_queue = rcv_queue,
            .snd_buf = snd_buf,
            .rcv_buf = rcv_buf,
            .buffer = buffer,
        };

        kcp.conv = conv;
        kcp.token = token;
        kcp.user = user;
        kcp.mss = kcp.mtu - IKCP_OVERHEAD;

        return kcp;
    }
    pub fn deinit(self: *Kcp) void {
        self.snd_queue.deinit(self.allocator);
        self.rcv_queue.deinit(self.allocator);
        self.snd_buf.deinit(self.allocator);
        self.rcv_buf.deinit(self.allocator);
        self.allocator.free(self.buffer);
        if (self.acklist) |list| {
            self.allocator.free(list);
            self.acklist = null;
        }
        self.nrcv_buf = 0;
        self.nsnd_buf = 0;
        self.nrcv_que = 0;
        self.nsnd_que = 0;
        self.ackcount = 0;
    }
    // write log
    fn log(kcp: *Kcp, mask: u32, comptime fmt: []const u8, args: anytype) void {
        if (kcp.canlog(mask) == false) return;

        var buffer = std.mem.zeroes([1024]u8);
        const bufferLog = std.fmt.bufPrintZ(&buffer, fmt, args) catch {
            return;
        };

        if (kcp.writelogFunc) |_writeLog| {
            _writeLog(bufferLog, kcp, kcp.user);
        }
    }
    // check log mask
    inline fn canlog(kcp: *const Kcp, mask: u32) bool {
        if ((mask & kcp.logmask) == 0 or kcp.writelogFunc == null) return false;
        return true;
    }
    // output segment
    fn output(kcp: *Kcp, data: []const u8) usize {
        std.debug.assert(kcp.outputFunc != null);
        if (kcp.canlog(IKCP_LOG_OUT_OUTPUT)) {
            kcp.log(IKCP_LOG_OUT_OUTPUT, "[RO] {d} bytes", .{data.len});
        }
        if (data.len == 0) return 0;
        if (kcp.outputFunc) |_output| {
            return _output(data, kcp.conv, kcp.user);
        }
        return 0;
    }
    pub fn setOutput(self: *Kcp, func: ?OutputFunc) void {
        self.outputFunc = func;
    }

    //---------------------------------------------------------------------
    // user/upper level recv: returns size, returns below zero for EAGAIN
    //---------------------------------------------------------------------
    pub fn recv(self: *Kcp, buffer: []u8, ispeek: bool) !usize {
        var recover: usize = 0;

        if (self.rcv_queue.isEmpty()) {
            return error.kcp_recv_1;
        }

        // if (buffer.len < 0) len = -len;

        const peeksize = try self.peekSize();

        if (peeksize < 0) {
            return error.kcp_recv_2;
        }

        if (peeksize > buffer.len) {
            return error.kcp_recv_3;
        }
        if (self.nrcv_que >= self.rcv_wnd) {
            recover = 1;
        }
        // merge fragment
        var len: usize = 0;
        var p: *LoopQueue = self.rcv_queue.next;
        while (p != self.rcv_queue) {
            var fragment: u32 = 0;
            const seg = p.getSeg();

            p = p.next;

            std.mem.copyForwards(u8, buffer[len..], seg.data[0..seg.len]);
            len += seg.len;
            fragment = seg.frg;

            if (self.canlog(IKCP_LOG_OUT_RECV)) {
                self.log(IKCP_LOG_OUT_RECV, "recv sn={d}", .{seg.sn});
            }

            if (ispeek == false) {
                seg.node.delSelf();
                seg.node.deinit(self.allocator);
                self.nrcv_que -= 1;
            }

            if (fragment == 0)
                break;
        }

        std.debug.assert(len == peeksize);

        // move available data from rcv_buf -> rcv_queue
        while (!self.rcv_buf.isEmpty()) {
            const seg = self.rcv_buf.next.getSeg();
            if (seg.sn == self.rcv_nxt and self.nrcv_que < self.rcv_wnd) {
                seg.node.delSelf();
                self.nrcv_buf -= 1;
                self.rcv_queue.addTail(&seg.node);
                self.nrcv_que += 1;
                self.rcv_nxt += 1;
            } else {
                break;
            }
        }

        // fast recover
        if (self.nrcv_que < self.rcv_wnd and recover != 0) {
            // ready to send back IKCP_CMD_WINS in ikcp_flush
            // tell remote my window size
            self.probe |= IKCP_ASK_TELL;
        }

        return len;
    }
    //---------------------------------------------------------------------
    // peek data size
    //---------------------------------------------------------------------
    pub fn peekSize(self: *Kcp) !usize {
        if (self.rcv_queue.isEmpty()) {
            return error.kcp_peeksize_1;
        }
        var length: usize = 0;
        var seg = self.rcv_queue.next.getSeg();
        if (seg.frg == 0) {
            return seg.len;
        }
        if (self.nrcv_que < (seg.frg + 1)) {
            return error.kcp_peeksize_2;
        }
        var p = self.rcv_queue.next;
        while (p != self.rcv_queue) : (p = p.next) {
            seg = p.getSeg();
            length += seg.len;
            if (seg.frg == 0) break;
        }
        return length;
    }
    //---------------------------------------------------------------------
    // user/upper level send, returns below zero for error
    //---------------------------------------------------------------------
    pub fn send(self: *Kcp, _buffer: []const u8) !usize {
        var buffer = _buffer;
        std.debug.assert(self.mss > 0);
        var len: u32 = @truncate(buffer.len);
        if (len < 0) {
            return error.kcp_send1;
        }
        var sent: usize = 0;
        var count: u32 = 0;
        if (self.stream != 0) {
            if (!self.snd_queue.isEmpty()) {
                var old = self.snd_queue.prev.getSeg();
                if (old.len < self.mss) {
                    const capacity = self.mss - old.len;
                    const extend = if (len < capacity) len else capacity;
                    const seg = try Seg.init(self.allocator, old.len + extend);

                    self.snd_queue.addTail(&seg.node);
                    std.mem.copyForwards(u8, seg.data, old.data[0..old.len]);
                    std.mem.copyForwards(u8, seg.data[old.len..], buffer[0..extend]);
                    buffer = buffer[extend..];
                    seg.len = old.len + extend;
                    seg.frg = 0;
                    len -= extend;
                    old.node.delSelf();
                    old.node.deinit(self.allocator);
                    sent = extend;
                }
            }
            if (len <= 0) {
                return sent;
            }
        }
        if (len <= self.mss) {
            count = 1;
        } else {
            count = (len + self.mss - 1) / self.mss;
        }

        if (count >= IKCP_WND_RCV) {
            if (self.stream != 0 and sent > 0) {
                return sent;
            }
            return error.Send2;
        }

        if (count == 0) count = 1;

        // fragment
        for (0..count) |_i| {
            const i: u32 = @truncate(_i);
            const size = if (len > self.mss) self.mss else len;
            const seg = try Seg.init(self.allocator, size);

            if (buffer.len > 0) {
                std.mem.copyForwards(u8, seg.data, buffer[0..size]);
            } else {
                unreachable;
            }
            seg.len = size;
            seg.frg = if (self.stream == 0) (count - i - 1) else 0;
            seg.node.initSelf();
            self.snd_queue.addTail(&seg.node);
            self.nsnd_que += 1;
            buffer = buffer[size..];
            len -= size;
            sent += size;
        }

        return sent;
    }
    //---------------------------------------------------------------------
    // parse ack
    //---------------------------------------------------------------------
    pub fn updateAck(self: *Kcp, rtt: i32) void {
        var rto: i32 = 0;
        if (self.rx_srtt == 0) {
            self.rx_srtt = rtt;
            self.rx_rttval = @divTrunc(rtt, 2);
        } else {
            var delta = rtt - self.rx_srtt;
            if (delta < 0) delta = -delta;
            self.rx_rttval = @divTrunc((3 * self.rx_rttval + delta), 4);
            self.rx_srtt = @divTrunc((7 * self.rx_srtt + rtt), 8);
            if (self.rx_srtt < 1) self.rx_srtt = 1;
        }
        rto = self.rx_srtt + @as(i32, @bitCast(_imax_(self.interval, 4 * @as(u32, @bitCast(self.rx_rttval)))));
        self.rx_rto = @as(i32, @bitCast(_ibound_(@as(u32, @bitCast(self.rx_minrto)), @as(u32, @bitCast(rto)), IKCP_RTO_MAX)));
    }
    pub fn shrinkBuf(self: *Kcp) void {
        const p = self.snd_buf.next;
        if (p != self.snd_buf) {
            const seg = p.getSeg();
            self.snd_una = seg.sn;
        } else {
            self.snd_una = self.snd_nxt;
        }
    }
    pub fn parseAck(self: *Kcp, sn: u32) void {
        if (_itimediff(sn, self.snd_una) < 0 or _itimediff(sn, self.snd_nxt) >= 0)
            return;

        var p = self.snd_buf.next;
        var next = p;
        while (p != self.snd_buf) : (p = next) {
            const seg = p.getSeg();
            next = p.next;
            if (sn == seg.sn) {
                p.delSelf();
                seg.deinit(self.allocator);
                self.nsnd_buf -= 1;
                break;
            }
            if (_itimediff(sn, seg.sn) < 0) {
                break;
            }
        }
    }

    pub fn parseUna(self: *Kcp, una: u32) void {
        var p = self.snd_buf.next;
        var next = p;
        while (p != self.snd_buf) : (p = next) {
            const seg = p.getSeg();
            next = p.next;
            if (_itimediff(una, seg.sn) > 0) {
                p.delSelf();
                seg.deinit(self.allocator);
                self.nsnd_buf -= 1;
            } else {
                break;
            }
        }
    }
    pub fn parseFastack(self: *Kcp, sn: u32, ts: u32) void {
        if (_itimediff(sn, self.snd_una) < 0 or _itimediff(sn, self.snd_nxt) >= 0)
            return;

        var p = self.snd_buf.next;
        var next = p;
        while (p != self.snd_buf) : (p = next) {
            const seg = p.getSeg();
            next = p.next;
            if (_itimediff(sn, seg.sn) < 0) {
                break;
            } else if (sn != seg.sn) {
                if (IKCP_FASTACK_CONSERVE == false) {
                    seg.fastack += 1;
                } else {
                    if (_itimediff(ts, seg.ts) >= 0)
                        seg.fastack += 1;
                }
            }
        }
    }

    //---------------------------------------------------------------------
    // ack append
    //---------------------------------------------------------------------
    pub fn ackPush(self: *Kcp, sn: u32, ts: u32) !void {
        const newsize = self.ackcount + 1;

        if (newsize > self.ackblock) {
            var acklist: []u32 = undefined;
            var newblock: u32 = 8;

            while (newblock < newsize) : (newblock <<= 1) {}
            acklist = try self.allocator.alloc(u32, newblock * 2);

            if (self.acklist) |_acklist| {
                for (0..self.ackcount) |x| {
                    const base = x * 2;
                    acklist[base + 0] = _acklist[base + 0];
                    acklist[base + 1] = _acklist[base + 1];
                }
                self.allocator.free(_acklist);
            }

            self.acklist = acklist;
            self.ackblock = newblock;
        }
        if (self.acklist) |_acklist| {
            const ptr = _acklist[self.ackcount * 2 ..];
            ptr[0] = sn;
            ptr[1] = ts;
            self.ackcount += 1;
        }
    }
    pub fn ackGet(self: *Kcp, p: usize, sn: ?*u32, ts: ?*u32) void {
        if (self.acklist) |acklist| {
            const base = p * 2;
            if (sn) |_sn| _sn.* = acklist[base + 0];
            if (ts) |_ts| _ts.* = acklist[base + 1];
        }
    }

    //---------------------------------------------------------------------
    // parse data
    //---------------------------------------------------------------------
    pub fn parseData(self: *Kcp, newseg: *Seg) void {
        const sn = newseg.sn;
        var repeat: usize = 0;

        if (_itimediff(sn, self.rcv_nxt + self.rcv_wnd) >= 0 or
            _itimediff(sn, self.rcv_nxt) < 0)
        {
            newseg.deinit(self.allocator);
            return;
        }

        var p = self.rcv_buf.prev;
        var prev = p;
        while (p != self.rcv_buf) : (p = prev) {
            const seg = p.getSeg();
            prev = p.prev;
            if (seg.sn == sn) {
                repeat = 1;
                break;
            }
            if (_itimediff(sn, seg.sn) > 0) {
                break;
            }
        }

        if (repeat == 0) {
            newseg.node.initSelf();
            p.addHead(&newseg.node);
            self.nrcv_buf += 1;
        } else {
            newseg.deinit(self.allocator);
        }

        // move available data from rcv_buf -> rcv_queue
        while (!self.rcv_buf.isEmpty()) {
            const seg = self.rcv_buf.next.getSeg();
            if (seg.sn == self.rcv_nxt and self.nrcv_que < self.rcv_wnd) {
                seg.node.delSelf();
                self.nrcv_buf -= 1;
                self.rcv_queue.addTail(&seg.node);
                self.nrcv_que += 1;
                self.rcv_nxt += 1;
            } else {
                break;
            }
        }
    }
    //---------------------------------------------------------------------
    // input data
    //---------------------------------------------------------------------
    pub fn input(self: *Kcp, _data: []const u8) !usize {
        var data = @constCast(_data.ptr);
        const prev_una = self.snd_una;
        var maxack: u32 = 0;
        var latest_ts: u32 = 0;
        var flag: usize = 0;

        if (self.canlog(IKCP_LOG_OUT_INPUT)) {
            self.log(IKCP_LOG_OUT_INPUT, "[RI] {d} bytes", .{_data.len});
        }

        if (_data.len < IKCP_OVERHEAD) {
            return error.input1;
        }
        var size = _data.len;
        while (true) {
            var ts: u32 = 0;
            var sn: u32 = 0;
            var len: u32 = 0;
            var una: u32 = 0;
            var conv: u32 = 0;
            var token: u32 = 0;
            var wnd: u16 = 0;
            var cmd: u8 = 0;
            var frg: u8 = 0;
            var seg: *Seg = undefined;

            if (size < IKCP_OVERHEAD) {
                break;
            }
            data = ikcp_decode32u(data, &conv);
            if (conv != self.conv) {
                return error.input2;
            }
            data = ikcp_decode32u(data, &token);
            if (token != self.token) {
                return error.KcpTokenMismatch;
            }
            data = ikcp_decode8u(data, &cmd);
            data = ikcp_decode8u(data, &frg);
            data = ikcp_decode16u(data, &wnd);
            data = ikcp_decode32u(data, &ts);
            data = ikcp_decode32u(data, &sn);
            data = ikcp_decode32u(data, &una);
            data = ikcp_decode32u(data, &len);

            size -= IKCP_OVERHEAD;

            if (size < len or len < 0) return error.input3;

            if (cmd != IKCP_CMD_PUSH and cmd != IKCP_CMD_ACK and
                cmd != IKCP_CMD_WASK and cmd != IKCP_CMD_WINS)
                return error.input_4;

            self.rmt_wnd = wnd;
            self.parseUna(una);
            self.shrinkBuf();

            if (cmd == IKCP_CMD_ACK) {
                if (_itimediff(self.current, ts) >= 0) {
                    self.updateAck(_itimediff(self.current, ts));
                }
                self.parseAck(sn);
                self.shrinkBuf();
                if (flag == 0) {
                    flag = 1;
                    maxack = sn;
                    latest_ts = ts;
                } else {
                    if (_itimediff(sn, maxack) > 0) {
                        if (IKCP_FASTACK_CONSERVE == false) {
                            maxack = sn;
                            latest_ts = ts;
                        } else {
                            if (_itimediff(ts, latest_ts) > 0) {
                                maxack = sn;
                                latest_ts = ts;
                            }
                        }
                    }
                }
                if (self.canlog(IKCP_LOG_OUT_IN_ACK)) {
                    self.log(IKCP_LOG_OUT_IN_ACK, "input ack: sn={d} rtt={d} rto={d}", .{ sn, _itimediff(self.current, ts), self.rx_rto });
                }
            } else if (cmd == IKCP_CMD_PUSH) {
                if (self.canlog(IKCP_LOG_OUT_IN_DATA)) {
                    self.log(IKCP_LOG_OUT_IN_DATA, "input psh: sn={d} ts={d}", .{ sn, ts });
                }
                if (_itimediff(sn, self.rcv_nxt + self.rcv_wnd) < 0) {
                    try self.ackPush(sn, ts);
                    if (_itimediff(sn, self.rcv_nxt) >= 0) {
                        seg = try Seg.init(self.allocator, len);
                        seg.conv = conv;
                        seg.token = token;
                        seg.cmd = cmd;
                        seg.frg = frg;
                        seg.wnd = wnd;
                        seg.ts = ts;
                        seg.sn = sn;
                        seg.una = una;
                        seg.len = len;

                        if (len > 0) {
                            std.mem.copyForwards(u8, seg.data, data[0..len]);
                        }

                        self.parseData(seg);
                    }
                }
            } else if (cmd == IKCP_CMD_WASK) {
                // ready to send back IKCP_CMD_WINS in ikcp_flush
                // tell remote my window size
                self.probe |= IKCP_ASK_TELL;
                if (self.canlog(IKCP_LOG_OUT_IN_PROBE)) {
                    self.log(IKCP_LOG_OUT_IN_PROBE, "input probe", .{});
                }
            } else if (cmd == IKCP_CMD_WINS) {
                // do nothing
                if (self.canlog(IKCP_LOG_OUT_IN_WINS)) {
                    self.log(IKCP_LOG_OUT_IN_WINS, "input wins: {d}", .{wnd});
                }
            } else {
                return error.input4;
            }

            data += len;
            size -= len;
        }

        if (flag != 0) {
            self.parseFastack(maxack, latest_ts);
        }

        if (_itimediff(self.snd_una, prev_una) > 0) {
            if (self.cwnd < self.rmt_wnd) {
                const mss = self.mss;
                if (self.cwnd < self.ssthresh) {
                    self.cwnd += 1;
                    self.incr += mss;
                } else {
                    if (self.incr < mss) self.incr = mss;
                    self.incr += (mss * mss) / self.incr + (mss / 16);
                    if ((self.cwnd + 1) * mss <= self.incr) {
                        self.cwnd = (self.incr + mss - 1) / (if (mss > 0) mss else 1);
                    }
                }
                if (self.cwnd > self.rmt_wnd) {
                    self.cwnd = self.rmt_wnd;
                    self.incr = self.rmt_wnd * mss;
                }
            }
        }

        return 0;
    }

    pub fn wndUnused(self: *const Kcp) u32 {
        if (self.nrcv_que < self.rcv_wnd) {
            return self.rcv_wnd - self.nrcv_que;
        }
        return 0;
    }

    //---------------------------------------------------------------------
    // ikcp_flush
    //---------------------------------------------------------------------
    pub fn flush(kcp: *Kcp) !void {
        const current = kcp.current;
        const buffer: []u8 = kcp.buffer;
        var ptr = buffer.ptr;
        var count: usize = 0;
        var size: usize = 0;
        var resent: u32 = 0;
        var cwnd: u32 = 0;
        var rtomin: u32 = 0;
        var p: *LoopQueue = undefined;
        var change: usize = 0;
        var lost: usize = 0;
        var seg: *Seg = try Seg.init(kcp.allocator, 1);
        defer seg.deinit(kcp.allocator);
        // 'ikcp_update' haven't been called.
        if (kcp.updated == 0) return;

        seg.conv = kcp.conv;
        seg.token = kcp.token;
        seg.cmd = IKCP_CMD_ACK;
        seg.frg = 0;
        seg.wnd = kcp.wndUnused();
        seg.una = kcp.rcv_nxt;
        seg.len = 0;
        seg.sn = 0;
        seg.ts = 0;

        // flush acknowledges
        count = kcp.ackcount;
        for (0..count) |i| {
            size = (@intFromPtr(ptr) - @intFromPtr(buffer.ptr));
            if (size + IKCP_OVERHEAD > kcp.mtu) {
                _ = kcp.output(buffer[0..size]);
                ptr = buffer.ptr;
            }
            kcp.ackGet(i, &seg.sn, &seg.ts);
            ptr = seg.encode(ptr);
        }
        kcp.ackcount = 0;

        // probe window size (if remote window size equals zero)
        if (kcp.rmt_wnd == 0) {
            if (kcp.probe_wait == 0) {
                kcp.probe_wait = IKCP_PROBE_INIT;
                kcp.ts_probe = kcp.current + kcp.probe_wait;
            } else {
                if (_itimediff(kcp.current, kcp.ts_probe) >= 0) {
                    if (kcp.probe_wait < IKCP_PROBE_INIT)
                        kcp.probe_wait = IKCP_PROBE_INIT;
                    kcp.probe_wait += kcp.probe_wait / 2;
                    if (kcp.probe_wait > IKCP_PROBE_LIMIT)
                        kcp.probe_wait = IKCP_PROBE_LIMIT;
                    kcp.ts_probe = kcp.current + kcp.probe_wait;
                    kcp.probe |= IKCP_ASK_SEND;
                }
            }
        } else {
            kcp.ts_probe = 0;
            kcp.probe_wait = 0;
        }

        // flush window probing commands
        if (kcp.probe & IKCP_ASK_SEND != 0) {
            seg.cmd = IKCP_CMD_WASK;
            size = (@intFromPtr(ptr) - @intFromPtr(buffer.ptr));
            if (size + IKCP_OVERHEAD > kcp.mtu) {
                _ = kcp.output(buffer[0..size]);
                ptr = buffer.ptr;
            }
            ptr = seg.encode(ptr);
        }

        // flush window probing commands
        if (kcp.probe & IKCP_ASK_TELL != 0) {
            seg.cmd = IKCP_CMD_WINS;
            size = (@intFromPtr(ptr) - @intFromPtr(buffer.ptr));
            if (size + IKCP_OVERHEAD > kcp.mtu) {
                _ = kcp.output(buffer[0..size]);
                ptr = buffer.ptr;
            }
            ptr = seg.encode(ptr);
        }

        kcp.probe = 0;

        // calculate window size
        cwnd = _imin_(kcp.snd_wnd, kcp.rmt_wnd);
        if (kcp.nocwnd == 0) cwnd = _imin_(kcp.cwnd, cwnd);

        // move data from snd_queue to snd_buf
        while (_itimediff(kcp.snd_nxt, kcp.snd_una + cwnd) < 0) {
            var newseg: *Seg = undefined;
            if (kcp.snd_queue.isEmpty()) break;

            newseg = kcp.snd_queue.next.getSeg();
            newseg.node.delSelf();
            kcp.snd_buf.addTail(&newseg.node);
            kcp.nsnd_que -= 1;
            kcp.nsnd_buf += 1;

            newseg.conv = kcp.conv;
            newseg.token = kcp.token;
            newseg.cmd = IKCP_CMD_PUSH;
            newseg.wnd = seg.wnd;
            newseg.ts = current;
            newseg.sn = kcp.snd_nxt;
            kcp.snd_nxt += 1;
            newseg.una = kcp.rcv_nxt;
            newseg.resendts = current;
            newseg.rto = @intCast(kcp.rx_rto);
            newseg.fastack = 0;
            newseg.xmit = 0;
        }

        // calculate resent
        resent = @intCast(if (kcp.fastresend > 0) kcp.fastresend else 0xffffffff);
        rtomin = if (kcp.nodelay == 0) (@as(u32, @intCast(kcp.rx_rto)) >> 3) else 0;

        // flush data segments
        p = kcp.snd_buf.next;
        while (p != kcp.snd_buf) : (p = p.next) {
            const segment = p.getSeg();
            var needsend: usize = 0;
            if (segment.xmit == 0) {
                needsend = 1;
                segment.xmit += 1;
                segment.rto = @intCast(kcp.rx_rto);
                segment.resendts = current + segment.rto + rtomin;
            } else if (_itimediff(current, segment.resendts) >= 0) {
                needsend = 1;
                segment.xmit += 1;
                kcp.xmit += 1;
                if (kcp.nodelay == 0) {
                    segment.rto += _imax_(segment.rto, @intCast(kcp.rx_rto));
                } else {
                    const step: u32 = if (kcp.nodelay < 2) segment.rto else @as(u32, @intCast(kcp.rx_rto));
                    segment.rto += step / 2;
                }
                segment.resendts = current + segment.rto;
                lost = 1;
            } else if (segment.fastack >= resent) {
                if (segment.xmit <= kcp.fastlimit or
                    kcp.fastlimit <= 0)
                {
                    needsend = 1;
                    segment.xmit += 1;
                    segment.fastack = 0;
                    segment.resendts = current + segment.rto;
                    change += 1;
                }
            }

            if (needsend != 0) {
                var need: usize = 0;
                segment.ts = current;
                segment.wnd = seg.wnd;
                segment.una = kcp.rcv_nxt;

                size = (@intFromPtr(ptr) - @intFromPtr(buffer.ptr));
                need = IKCP_OVERHEAD + segment.len;

                if (size + need > kcp.mtu) {
                    _ = kcp.output(buffer[0..size]);
                    ptr = buffer.ptr;
                }

                ptr = segment.encode(ptr);

                if (segment.len > 0) {
                    std.mem.copyForwards(u8, ptr[0..segment.len], segment.data[0..segment.len]);
                    ptr += segment.len;
                }

                if (segment.xmit >= kcp.dead_link) {
                    kcp.state = @bitCast(@as(i32, -1));
                }
            }
        }

        // flash remain segments
        size = (@intFromPtr(ptr) - @intFromPtr(buffer.ptr));
        if (size > 0) {
            _ = kcp.output(buffer[0..size]);
        }

        // update ssthresh
        if (change != 0) {
            const inflight: u32 = kcp.snd_nxt - kcp.snd_una;
            kcp.ssthresh = inflight / 2;
            if (kcp.ssthresh < IKCP_THRESH_MIN)
                kcp.ssthresh = IKCP_THRESH_MIN;
            kcp.cwnd = kcp.ssthresh + resent;
            kcp.incr = kcp.cwnd * kcp.mss;
        }

        if (lost != 0) {
            kcp.ssthresh = cwnd / 2;
            if (kcp.ssthresh < IKCP_THRESH_MIN)
                kcp.ssthresh = IKCP_THRESH_MIN;
            kcp.cwnd = 1;
            kcp.incr = kcp.mss;
        }

        if (kcp.cwnd < 1) {
            kcp.cwnd = 1;
            kcp.incr = kcp.mss;
        }
    }

    //---------------------------------------------------------------------
    // update state (call it repeatedly, every 10ms-100ms), or you can ask
    // ikcp_check when to call it again (without ikcp_input/_send calling).
    // 'current' - current timestamp in millisec.
    //---------------------------------------------------------------------
    pub fn update(kcp: *Kcp, current: u32) !void {
        var slap: i64 = 0;

        kcp.current = current;

        if (kcp.updated == 0) {
            kcp.updated = 1;
            kcp.ts_flush = kcp.current;
        }

        slap = _itimediff(kcp.current, kcp.ts_flush);

        if (slap >= 10000 or slap < -10000) {
            kcp.ts_flush = kcp.current;
            slap = 0;
        }

        if (slap >= 0) {
            kcp.ts_flush += kcp.interval;
            if (_itimediff(kcp.current, kcp.ts_flush) >= 0) {
                kcp.ts_flush = kcp.current + kcp.interval;
            }
            try kcp.flush();
        }
    }
    //---------------------------------------------------------------------
    // Determine when should you invoke ikcp_update:
    // returns when you should invoke ikcp_update in millisec, if there
    // is no ikcp_input/_send calling. you can call ikcp_update in that
    // time, instead of call update repeatly.
    // Important to reduce unnacessary ikcp_update invoking. use it to
    // schedule ikcp_update (eg. implementing an epoll-like mechanism,
    // or optimize ikcp_update when handling massive kcp connections)
    //---------------------------------------------------------------------
    pub fn check(kcp: *const Kcp, current: u32) u32 {
        var ts_flush = kcp.ts_flush;
        var tm_flush: i32 = 0x7fffffff;
        var tm_packet: i32 = 0x7fffffff;
        var minimal: u32 = 0;
        var p: *LoopQueue = undefined;

        if (kcp.updated == 0) {
            return current;
        }

        if (_itimediff(current, ts_flush) >= 10000 or
            _itimediff(current, ts_flush) < -10000)
        {
            ts_flush = current;
        }

        if (_itimediff(current, ts_flush) >= 0) {
            return current;
        }

        tm_flush = _itimediff(ts_flush, current);

        p = kcp.snd_buf.next;
        while (p != kcp.snd_buf) : (p = p.next) {
            const seg = p.getSeg();
            const diff = _itimediff(seg.resendts, current);
            if (diff <= 0) {
                return current;
            }
            if (diff < tm_packet) tm_packet = diff;
        }

        minimal = if (tm_packet < tm_flush) tm_packet else tm_flush;
        if (minimal >= kcp.interval) minimal = kcp.interval;

        return current + minimal;
    }

    pub fn setMTU(kcp: *Kcp, mtu: usize) !usize {
        var buffer: []u8 = undefined;
        if (mtu < 50 or mtu < IKCP_OVERHEAD)
            return error.setmtu;
        buffer = try kcp.allocator.alloc(u8, (mtu + IKCP_OVERHEAD) * 3);
        kcp.mtu = mtu;
        kcp.mss = kcp.mtu - IKCP_OVERHEAD;
        if (kcp.buffer) |_buffer| {
            kcp.allocator.free(_buffer);
        }
        kcp.buffer = buffer;
        return 0;
    }

    pub inline fn setInterval(kcp: *Kcp, _interval: u32) void {
        kcp.interval = _ibound_(10, _interval, 5000);
    }

    pub fn noDelay(kcp: *Kcp, _nodelay: u32, _interval: u32, resend: usize, nc: usize) usize {
        if (_nodelay >= 0) {
            kcp.nodelay = _nodelay;
            if (_nodelay > 0) {
                kcp.rx_minrto = IKCP_RTO_NDL;
            } else {
                kcp.rx_minrto = IKCP_RTO_MIN;
            }
        }
        if (_interval >= 0) {
            kcp.setInterval(_interval);
        }
        if (resend >= 0) {
            kcp.fastresend = resend;
        }
        if (nc >= 0) {
            kcp.nocwnd = nc;
        }
        return 0;
    }

    pub fn wndSize(kcp: *Kcp, sndwnd: u32, rcvwnd: u32) usize {
        if (sndwnd > 0) {
            kcp.snd_wnd = sndwnd;
        }
        if (rcvwnd > 0) { // must >= max fragment size
            kcp.rcv_wnd = _imax_(rcvwnd, IKCP_WND_RCV);
        }
        return 0;
    }

    pub fn waitSnd(kcp: *const Kcp) u32 {
        return kcp.nsnd_buf + kcp.nsnd_que;
    }
};
