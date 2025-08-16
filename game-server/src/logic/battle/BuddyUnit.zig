const std = @import("std");
const protocol = @import("protocol");

const Buddy = @import("../player/Buddy.zig");
const Allocator = std.mem.Allocator;

const Self = @This();

const assisting_buddy_id: u32 = 50001;

buddy_id: u32,
team_type: BuddyTeamType,
// TODO: buddy properties

pub fn init(buddy: *const Buddy, team_type: BuddyTeamType) !Self {
    return .{
        .buddy_id = buddy.id,
        .team_type = team_type,
    };
}

pub fn initAssistingBuddy() !Self {
    return .{
        .buddy_id = assisting_buddy_id,
        .team_type = .assisting,
    };
}

pub fn deinit(_: *Self) void {}

pub fn toProto(self: *const Self, allocator: Allocator) !protocol.ByName(.BuddyUnitInfo) {
    return protocol.makeProto(.BuddyUnitInfo, .{
        .buddy_id = self.buddy_id,
        .team_type = @intFromEnum(self.team_type),
    }, allocator);
}

pub const BuddyTeamType = enum(i32) {
    fighting = 2,
    assisting = 3,
};
