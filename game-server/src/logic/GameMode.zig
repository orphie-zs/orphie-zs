const std = @import("std");
const protocol = @import("protocol");

const Globals = @import("../Globals.zig");
const PlayerInfo = @import("player/PlayerInfo.zig");
const HallScene = @import("scene/HallScene.zig");
const FightScene = @import("scene/FightScene.zig");
const HadalZoneScene = @import("scene/HadalZoneScene.zig");
const Scene = @import("scene.zig").Scene;
const Dungeon = @import("Dungeon.zig");
const TemplateCollection = @import("../data/templates.zig").TemplateCollection;
const Allocator = std.mem.Allocator;

const Self = @This();

allocator: Allocator,
scene: Scene,
dungeon: ?Dungeon,

pub fn loadHallState(player_info: *PlayerInfo, globals: *const Globals, allocator: Allocator) !Self {
    var hall = try HallScene.create(
        player_info,
        &globals.templates,
        &globals.event_graph_map,
        allocator,
    );

    errdefer hall.destroy();
    try hall.onCreate();
    try hall.onEnter();

    return .{
        .allocator = allocator,
        .scene = .{ .hall = hall },
        .dungeon = null,
    };
}

pub fn loadFightState(player_info: *PlayerInfo, templates: *const TemplateCollection, avatar_ids: []const u32, allocator: Allocator) !Self {
    var dungeon = Dungeon.init(player_info, templates, allocator);
    errdefer dungeon.deinit();

    for (avatar_ids) |id| {
        try dungeon.addAvatarFighter(id, Dungeon.PackageType.player);
    }

    // TODO: pass proper quest information, scene_id should be obtained from Quest/BattleEventTemplate
    dungeon.setDungeonQuest(0, 12254000);

    return .{
        .allocator = allocator,
        .scene = .{ .fight = try FightScene.create(19800014, 290, allocator) },
        .dungeon = dungeon,
    };
}

const hadal_static_zone_group: u32 = 61;

pub fn loadHadalZoneState(
    player_info: *PlayerInfo,
    templates: *const TemplateCollection,
    first_room_avatars: []const u32,
    second_room_avatars: []const u32,
    zone_id: u32,
    layer_index: u32,
    layer_item_id: u32,
    allocator: Allocator,
) !Self {
    var dungeon = Dungeon.init(player_info, templates, allocator);
    errdefer dungeon.deinit();

    for (first_room_avatars) |id| {
        try dungeon.addAvatarFighter(id, Dungeon.PackageType.player);
    }

    for (second_room_avatars) |id| {
        try dungeon.addAvatarFighter(id, Dungeon.PackageType.player);
    }

    const base_zone_id = if (zone_id / 1000 != hadal_static_zone_group) ((zone_id / 1000) * 1000) + 1 else zone_id;

    const zone_info_template = for (templates.zone_info_template_tb.items) |tmpl| {
        if (tmpl.zone_id == @as(i32, @intCast(base_zone_id)) and tmpl.layer_index == @as(i32, @intCast(layer_index))) {
            break tmpl;
        }
    } else return error.InvalidZoneLayerIndex;

    // TODO: get time period from ZoneInfoTemplate and use it.

    const layer_info_template = templates.getConfigByKey(.layer_info_template_tb, zone_info_template.layer_id) orelse return error.InvalidLayer;

    // TODO: get weather from LayerInfoTemplate and use it.
    _ = layer_info_template;

    const quest_template = templates.getConfigByKey(.hadal_zone_quest_template_tb, zone_info_template.layer_id) orelse return error.MissingQuestForLayer;
    dungeon.setDungeonQuest(0, @intCast(quest_template.quest_id));

    return .{
        .allocator = allocator,
        .scene = .{ .hadal_zone = try HadalZoneScene.create(
            @intCast(zone_info_template.layer_id),
            zone_id,
            layer_index,
            layer_item_id,
            first_room_avatars,
            second_room_avatars,
            allocator,
        ) },
        .dungeon = dungeon,
    };
}

pub fn flushNetEvents(self: *Self, context: anytype) !void {
    try self.flushTransitionEvent(context);

    switch (self.scene) {
        inline else => |scene| {
            if (@hasDecl(std.meta.Child(@TypeOf(scene)), "flushNetEvents")) {
                try scene.flushNetEvents(context);
            }
        },
    }
}

fn flushTransitionEvent(self: *Self, context: anytype) !void {
    switch (self.scene) {
        inline else => |scene| {
            if (scene.clearTransitionState()) {
                var enter_notify = protocol.makeProto(.EnterSceneScNotify, .{
                    .scene = try scene.toProto(context.arena),
                }, context.arena);

                if (self.dungeon) |dungeon| {
                    protocol.setFields(&enter_notify, .{
                        .dungeon = try dungeon.toProto(context.arena),
                    });
                }

                try context.notify(enter_notify);
            }
        },
    }
}

pub fn deinit(self: *Self) void {
    self.scene.deinit();

    if (self.dungeon != null) {
        self.dungeon.?.deinit();
        self.dungeon = null;
    }
}
