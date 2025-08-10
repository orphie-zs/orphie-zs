const std = @import("std");
const PlayerSession = @import("PlayerSession.zig");

const Self = @This();
const ProtocolUnitList = std.ArrayListUnmanaged(ProtocolUnit);

session: *PlayerSession,
arena: std.mem.Allocator,
rsp: ?ProtocolUnit,
notifies: ProtocolUnitList,

pub fn init(session: *PlayerSession, arena: std.mem.Allocator) Self {
    return .{
        .session = session,
        .arena = arena,
        .rsp = null,
        .notifies = ProtocolUnitList.empty,
    };
}

pub fn deinit(self: *Self) void {
    self.notifies.deinit(self.arena);
}

pub fn notify(self: *Self, proto: anytype) !void {
    defer proto.deinit();

    const buffer = try proto.encode(self.arena);
    const cmd_id = proto.getCmdId();

    (try self.notifies.addOne(self.arena)).* = .{
        .cmd_id = cmd_id,
        .buffer = buffer,
    };
}

const ProtocolUnit = struct {
    cmd_id: u16,
    buffer: []u8,
};
