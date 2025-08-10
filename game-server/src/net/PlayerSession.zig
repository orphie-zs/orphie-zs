const std = @import("std");
const protocol = @import("protocol");

const Kcp = @import("kcp.zig").Kcp;
const NetPacket = @import("packet.zig").NetPacket;
const Globals = @import("../Globals.zig");
const NetContext = @import("NetContext.zig");
const NetConnection = @import("NetConnection.zig");
const PlayerInfo = @import("../logic/player/PlayerInfo.zig");
const GameMode = @import("../logic/GameMode.zig");

const Allocator = std.mem.Allocator;
const EndPoint = @import("network").EndPoint;

const log = std.log;
const Self = @This();

const PacketHandlers = struct {
    pub const player = @import("../handlers/player.zig");
    pub const avatar = @import("../handlers/avatar.zig");
    pub const item = @import("../handlers/item.zig");
    pub const quest = @import("../handlers/quest.zig");
    pub const buddy = @import("../handlers/buddy.zig");
    pub const misc = @import("../handlers/misc.zig");
    pub const tips = @import("../handlers/tips.zig");
    pub const world = @import("../handlers/world.zig");
    pub const map = @import("../handlers/map.zig");
    pub const time = @import("../handlers/time.zig");
};

allocator: Allocator,
connection: NetConnection,
globals: *const Globals,
player_uid: ?u32,
player_info: ?PlayerInfo,
game_mode: ?GameMode,

pub fn init(allocator: Allocator, conv: u32, token: u32, ep: EndPoint, globals: *const Globals) !*Self {
    const ptr = try allocator.create(Self);
    errdefer allocator.destroy(ptr);

    const kcp = try Kcp.init(allocator, conv, token, @intFromPtr(ptr));

    ptr.* = .{
        .allocator = allocator,
        .connection = .init(allocator, ep, kcp, globals.initial_xorpad),
        .globals = globals,
        .player_uid = null,
        .player_info = null,
        .game_mode = null,
    };

    return ptr;
}

pub fn deinit(self: *Self) void {
    if (self.player_info != null) {
        self.player_info.?.deinit();
    }

    if (self.game_mode != null) {
        self.game_mode.?.deinit();
    }

    self.connection.deinit();
    self.allocator.destroy(self);
}

pub fn onReceive(self: *Self, buffer: []const u8) !void {
    try self.connection.onReceive(buffer);
    var recv_buffer: ?[]u8 = null;

    while (self.connection.peekSize()) |size| {
        var payload: ?[]u8 = null;

        if (recv_buffer == null) {
            recv_buffer = try self.allocator.alloc(u8, size);
            payload = recv_buffer.?;
        } else if (size > recv_buffer.?.len) {
            self.allocator.free(recv_buffer.?);

            recv_buffer = try self.allocator.alloc(u8, size);
            payload = recv_buffer.?;
        } else {
            payload = recv_buffer.?[0..size];
        }

        const message = (try self.connection.nextMessage(payload.?)).?;
        try self.processMessage(message);
    }

    if (recv_buffer) |buf| self.allocator.free(buf);
    try self.connection.flush();
}

fn isMessageAllowedInCurrentState(self: *Self, cmd_id: u16) bool {
    if (self.player_info) |_| return true;

    return cmd_id == protocol.ByName(.PlayerGetTokenCsReq).CmdId or cmd_id == protocol.ByName(.PlayerLoginCsReq).CmdId;
}

fn processMessage(self: *Self, packet: NetPacket) !void {
    if (!self.isMessageAllowedInCurrentState(packet.cmd_id)) {
        log.err("received message {?s} in invalid state!", .{protocol.CmdNames[packet.cmd_id]});
        return error.NotAllowedInCurrentState;
    }

    var arena = std.heap.ArenaAllocator.init(self.allocator);
    defer arena.deinit();

    const head = try protocol.head.PacketHead.decode(packet.head, arena.allocator());

    log.info("received packet with cmd_id: {}, payload: {}", .{
        packet.cmd_id,
        std.fmt.fmtSliceHexUpper(packet.body),
    });

    var context = NetContext.init(self, arena.allocator());
    defer context.deinit();

    if (try handleMessage(&context, PacketHandlers, &packet)) {
        if (self.player_info != null) {
            const player_info = &self.player_info.?;
            if (player_info.hasChangedFields()) {
                const player_sync = try player_info.ackPlayerSync(context.arena);
                defer player_sync.deinit();

                player_info.reset();
                try self.connection.send(player_sync.getCmdId(), try player_sync.encode(context.arena), 0);
            }
        }

        if (self.game_mode != null) {
            try self.game_mode.?.flushNetEvents(&context);
        }

        for (context.notifies.items) |notify| {
            try self.connection.send(notify.cmd_id, notify.buffer, 0);
        }

        if (context.rsp) |rsp| {
            try self.connection.send(rsp.cmd_id, rsp.buffer, head.packet_id);
        }
    } else if (head.packet_id != 0) {
        log.warn("unhandled request: {?s} ({})", .{ protocol.CmdNames[packet.cmd_id], packet.cmd_id });
        try self.connection.send(protocol.DummyMessage.CmdId, &.{}, head.packet_id);
    } else {
        log.warn("unhandled notify: {?s} ({})", .{ protocol.CmdNames[packet.cmd_id], packet.cmd_id });
    }
}

inline fn handleMessage(context: *NetContext, comptime T: type, packet: *const NetPacket) !bool {
    @setEvalBranchQuota(1_000_000);
    const cmd_id_tag = std.meta.intToEnum(protocol.CmdIds, packet.cmd_id) catch return false;

    switch (cmd_id_tag) {
        inline else => |cmd_id| {
            inline for (comptime std.meta.declarations(T)) |decl| {
                const imported_handler = @field(T, decl.name);
                inline for (comptime std.meta.declarations(imported_handler)) |handler_decl| {
                    switch (@typeInfo(@TypeOf(@field(imported_handler, handler_decl.name)))) {
                        .@"fn" => |fn_info| {
                            const Message = fn_info.params[1].type.?;

                            if (@hasDecl(Message, "CmdId")) {
                                const t_enum_value: protocol.CmdIds = @enumFromInt(@field(Message, "CmdId"));
                                if (cmd_id == t_enum_value) {
                                    const req = try @field(Message, "decode")(packet.body, context.arena);
                                    defer req.deinit();

                                    if (!(comptime std.mem.endsWith(u8, @typeName(fn_info.return_type.?), "void"))) {
                                        const rsp = try @field(imported_handler, handler_decl.name)(context, req);
                                        defer rsp.deinit();

                                        context.rsp = .{
                                            .cmd_id = rsp.getCmdId(),
                                            .buffer = try rsp.encode(context.arena),
                                        };
                                    } else {
                                        // Notify handlers do not return anything
                                        try @field(imported_handler, handler_decl.name)(context, req);
                                    }

                                    log.info("successfully handled message of type {s}", .{@tagName(cmd_id)});
                                    return true;
                                }
                            }
                        },
                        else => {},
                    }
                }
            }
        },
    }

    return false;
}
