const std = @import("std");
const protocol = @import("protocol");

const Allocator = std.mem.Allocator;
const ByName = protocol.ByName;
const String = protocol.protobuf.ManagedString;
const scene_base = @import("../scene.zig");
const SceneType = scene_base.SceneType;
const LocalPlayType = scene_base.LocalPlayType;

const Self = @This();

const room_count: usize = 2;

const hadal_zone_alivecount_zone_id: u32 = 61002;
const hadal_zone_bosschallenge_zone_group: u32 = 69;

const hadal_zone_enemy_property_scale: u32 = 19;
const hadal_zone_bosschallenge_enemy_property_scale: u32 = 33;

gpa: Allocator,
scene_id: u32,
zone_id: u32,
layer_index: u32,
layer_item_id: u32,
first_room_avatars: [3]?u32,
second_room_avatars: [3]?u32,
buddy_ids: [room_count]u32,
is_in_transition: bool = true,

pub fn create(
    scene_id: u32,
    zone_id: u32,
    layer_index: u32,
    layer_item_id: u32,
    first_room_avatar_list: []const u32,
    second_room_avatar_list: []const u32,
    first_room_buddy_id: u32,
    second_room_buddy_id: u32,
    gpa: Allocator,
) !*Self {
    const ptr = try gpa.create(Self);

    const first_room_avatars = initAvatarList(first_room_avatar_list);
    const second_room_avatars = initAvatarList(second_room_avatar_list);

    ptr.* = .{
        .gpa = gpa,
        .scene_id = scene_id,
        .zone_id = zone_id,
        .layer_index = layer_index,
        .layer_item_id = layer_item_id,
        .first_room_avatars = first_room_avatars,
        .second_room_avatars = second_room_avatars,
        .buddy_ids = .{ first_room_buddy_id, second_room_buddy_id },
    };

    return ptr;
}

pub fn destroy(self: *Self) void {
    self.gpa.destroy(self);
}

fn initAvatarList(avatar_id_list: []const u32) [3]?u32 {
    var avatars = [_]?u32{null} ** 3;

    for (0..@min(3, avatar_id_list.len)) |i| {
        avatars[i] = avatar_id_list[i];
    }

    return avatars;
}

pub fn clearTransitionState(self: *Self) bool {
    if (self.is_in_transition) {
        self.is_in_transition = false;
        return true;
    }

    return false;
}

fn getPlayTypeByZoneId(zone_id: u32) LocalPlayType {
    if (zone_id == hadal_zone_alivecount_zone_id) return .hadal_zone_alivecount;
    if ((zone_id / 1000) == hadal_zone_bosschallenge_zone_group) return .hadal_zone_bosschallenge;

    return .hadal_zone;
}

fn getEnemyPropertyScaleByPlayType(play_type: LocalPlayType) u32 {
    return switch (play_type) {
        .hadal_zone_bosschallenge => hadal_zone_bosschallenge_enemy_property_scale,
        else => hadal_zone_enemy_property_scale,
    };
}

pub fn toProto(self: *const Self, allocator: Allocator) !ByName(.SceneData) {
    var hadal_zone_data = protocol.makeProto(.HadalZoneSceneData, .{
        .scene_perform = protocol.makeProto(.ScenePerformInfo, .{}, allocator),
        .zone_id = self.zone_id,
        .layer_index = self.layer_index,
        .layer_item_id = self.layer_item_id,
        .first_room_buddy_id = self.buddy_ids[0],
        .second_room_buddy_id = self.buddy_ids[1],
    }, allocator);

    for (self.first_room_avatars) |avatar_id| {
        if (avatar_id) |id| try protocol.addToList(&hadal_zone_data, .first_room_avatar_id_list, id);
    }

    for (self.second_room_avatars) |avatar_id| {
        if (avatar_id) |id| try protocol.addToList(&hadal_zone_data, .second_room_avatar_id_list, id);
    }

    const play_type = getPlayTypeByZoneId(self.zone_id);

    return protocol.makeProto(.SceneData, .{
        .scene_type = @intFromEnum(SceneType.hadal_zone),
        .scene_id = self.scene_id,
        .play_type = @intFromEnum(play_type),
        .enemy_property_scale = getEnemyPropertyScaleByPlayType(play_type),
        .hadal_zone_scene_data = hadal_zone_data,
    }, allocator);
}
