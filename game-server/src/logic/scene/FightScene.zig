const std = @import("std");
const protocol = @import("protocol");

const Allocator = std.mem.Allocator;
const ByName = protocol.ByName;
const String = protocol.protobuf.ManagedString;
const SceneType = @import("../scene.zig").SceneType;

const Self = @This();

gpa: Allocator,
scene_id: u32,
play_type: u32,
is_in_transition: bool = true,

pub fn create(scene_id: u32, play_type: u32, gpa: Allocator) !*Self {
    const ptr = try gpa.create(Self);

    ptr.* = .{
        .gpa = gpa,
        .scene_id = scene_id,
        .play_type = play_type,
    };

    return ptr;
}

pub fn destroy(self: *Self) void {
    self.gpa.destroy(self);
}

pub fn clearTransitionState(self: *Self) bool {
    if (self.is_in_transition) {
        self.is_in_transition = false;
        return true;
    }

    return false;
}

pub fn toProto(self: *const Self, allocator: Allocator) !ByName(.SceneData) {
    const fight_data = protocol.makeProto(.FightSceneData, .{
        .scene_reward = protocol.makeProto(.SceneRewardInfo, .{}, allocator),
        .scene_perform = protocol.makeProto(.ScenePerformInfo, .{}, allocator),
    }, allocator);

    return protocol.makeProto(.SceneData, .{
        .scene_type = @intFromEnum(SceneType.fight),
        .scene_id = self.scene_id,
        .play_type = self.play_type,
        .fight_scene_data = fight_data,
    }, allocator);
}
