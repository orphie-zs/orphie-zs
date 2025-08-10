const std = @import("std");
const network = @import("network");
const protocol = @import("protocol");

const Kcp = @import("kcp.zig").Kcp;
const NetPacket = @import("packet.zig").NetPacket;
const Mt64 = @import("common").util.mt19937.MT19937_64;

const Allocator = std.mem.Allocator;
const EndPoint = network.EndPoint;

const log = std.log;
const Self = @This();

allocator: Allocator,
init_ts: i64,
initial_xorpad: []const u8,
session_xorpad: ?[]const u8,
end_point: EndPoint,
kcp: Kcp,
packet_id_counter: u32,

pub fn init(allocator: Allocator, ep: EndPoint, kcp: Kcp, initial_xorpad: []const u8) Self {
    return .{
        .allocator = allocator,
        .init_ts = std.time.milliTimestamp(),
        .initial_xorpad = initial_xorpad,
        .session_xorpad = null,
        .end_point = ep,
        .kcp = kcp,
        .packet_id_counter = 0,
    };
}

pub fn deinit(self: *Self) void {
    if (self.session_xorpad) |session_xorpad_ptr| {
        self.allocator.free(session_xorpad_ptr);
    }

    self.kcp.deinit();
}

pub fn send(self: *Self, cmd_id: u16, body: []u8, ack_packet_id: u32) !void {
    const is_first_send = cmd_id == protocol.ByName(.PlayerGetTokenScRsp).CmdId;

    const head = try (protocol.head.PacketHead{
        .packet_id = self.packet_id_counter,
        .ack_packet_id = ack_packet_id,
    }).encode(self.allocator);
    defer self.allocator.free(head);

    self.packet_id_counter += 1;

    const xorpad = self.currentXorpad(is_first_send);
    for (0..body.len) |i| {
        body[i] ^= xorpad[i % xorpad.len];
    }

    const buffer = try self.allocator.alloc(u8, NetPacket.minimal_length + head.len + body.len);
    defer self.allocator.free(buffer);

    NetPacket.encode(buffer, cmd_id, head, body);
    _ = try self.kcp.send(buffer);
}

pub fn onReceive(self: *Self, buffer: []const u8) !void {
    _ = try self.kcp.input(buffer);
    try self.kcp.update(self.millisSinceInit());
}

pub fn peekSize(self: *Self) ?usize {
    return self.kcp.peekSize() catch null;
}

pub fn nextMessage(self: *Self, payload: []u8) !?NetPacket {
    _ = try self.kcp.recv(payload, false);
    var packet: NetPacket = undefined;

    if (NetPacket.decode(payload, &packet)) |_| {
        const xorpad = self.currentXorpad(false);
        for (0..packet.body.len) |i| {
            packet.body[i] ^= xorpad[i % xorpad.len];
        }

        return packet;
    } else |err| {
        log.err("failed to decode packet: {}", .{err});
        return null;
    }
}

pub fn flush(self: *Self) !void {
    try self.kcp.flush();
}

pub fn initSessionKey(self: *Self, rand_key: u64) !void {
    if (self.session_xorpad) |prev_xorpad| {
        // shouldn't happen!
        self.allocator.free(prev_xorpad);
    }

    const new_xorpad = try self.allocator.alloc(u8, 4096);
    var mt = Mt64.init(rand_key);

    for (0..512) |i| {
        std.mem.writeInt(u64, @ptrCast(new_xorpad[i * 8 .. (i + 1) * 8]), mt.get(), .big);
    }

    self.session_xorpad = new_xorpad;
}

fn currentXorpad(self: *Self, first_send: bool) []const u8 {
    return if (first_send or self.session_xorpad == null) self.initial_xorpad else self.session_xorpad.?;
}

fn millisSinceInit(self: *Self) u32 {
    return @intCast(std.time.milliTimestamp() - self.init_ts);
}
