const std = @import("std");
const pb_action = @import("protocol").action;

const HallScene = @import("../../logic/scene/HallScene.zig");
const SceneUnitManager = @import("../../logic/SceneUnitManager.zig");
const EventRunContext = @import("../../logic/event/LevelEventGraph.zig").EventRunContext;
const Allocator = std.mem.Allocator;

pub const ActionCreateNpcCfg = struct {
    pub const tag = "Share.CActionCreateNPCCfg";
    pub const action_type: i32 = 3001;

    id: u32,
    tag_id: u32 = 0,
    tag_ids: []const u32 = &.{},

    pub fn run(self: *const @This(), context: *EventRunContext) !void {
        switch (context.graph.level) {
            .hall => |hall| {
                if (self.tag_id != 0) try hall.createNpc(context.graph.section_id, self.tag_id);
                for (self.tag_ids) |tag_id| try hall.createNpc(context.graph.section_id, tag_id);
            },
            else => {},
        }
    }
};

pub const InteractScaleCfg = struct {
    x: f64 = 0,
    y: f64 = 0,
    z: f64 = 0,
    w: f64 = 0,
    r: f64 = 0,
};

pub const ActionChangeInteractCfg = struct {
    pub const tag = "Share.CActionChangeInteractCfg";
    pub const action_type: i32 = 3003;

    const default_interact_name = "A";

    id: u32,
    interact_id: u32,
    tag_ids: []const u32,
    interact_scale: InteractScaleCfg,

    pub fn run(self: *const @This(), context: *EventRunContext) !void {
        switch (context.graph.level) {
            .hall => |hall| {
                for (self.tag_ids) |tag_id| {
                    if (hall.unit_manager.getSceneUnit(context.graph.section_id, tag_id)) |unit| {
                        var interact = SceneUnitManager.InteractInfo.init(@intCast(self.interact_id), default_interact_name);
                        interact.setScaleFromConfig(self.interact_scale);
                        unit.setInteract(.npc, interact);
                    }
                }
            },
            else => {},
        }
    }
};

pub const ActionOpenUI = struct {
    pub const tag = "Share.CActionOpenUI";
    pub const action_type: i32 = 5;

    id: u32,
    ui: []const u8,
    store_template_id: i32,

    pub fn run(_: *const @This(), context: *EventRunContext) !void {
        context.interrupt();
    }

    pub fn toProto(self: *const @This(), arena: Allocator) !pb_action.ActionOpenUi {
        return .{
            .ui = try .copy(self.ui, arena),
            .store_template_id = self.store_template_id,
        };
    }
};

pub const ActionSetBgm = struct {
    pub const tag = "Share.CActionSetBGM";
    pub const action_type: i32 = 3022;

    id: u32,
    main_city_music_id: u32,

    pub fn run(self: *const @This(), context: *EventRunContext) !void {
        switch (context.graph.level) {
            .hall => |hall| {
                hall.bgm_id = self.main_city_music_id;
            },
            else => {},
        }
    }
};

pub const ActionSetMainCityObjectState = struct {
    pub const tag = "Share.CActionSetMainCityObjectState";
    pub const action_type: i32 = 3023;

    id: u32,
    object_state: []const struct { i32, i32 },

    pub fn jsonParseFromValue(allocator: std.mem.Allocator, value: std.json.Value, _: std.json.ParseOptions) !@This() {
        const object = switch (value) {
            .object => |obj| obj,
            else => return error.UnexpectedToken,
        };

        const id_value = object.get("id") orelse return error.MissingField;
        const id: u32 = switch (id_value) {
            .integer => |i| @intCast(i),
            else => return error.UnexpectedToken,
        };

        const object_state_value = object.get("object_state") orelse return error.MissingField;
        const object_state = switch (object_state_value) {
            .object => |obj| obj,
            else => return error.UnexpectedToken,
        };

        var object_state_list = try allocator.alloc(struct { i32, i32 }, object_state.count());
        var kvs = object_state.iterator();
        var i: usize = 0;
        while (kvs.next()) |entry| : (i += 1) {
            const object_id = std.fmt.parseInt(i32, entry.key_ptr.*, 10) catch return error.InvalidNumber;
            const state: i32 = switch (entry.value_ptr.*) {
                .integer => |v| @intCast(v),
                else => return error.InvalidNumber,
            };

            object_state_list[i] = .{ object_id, state };
        }

        return .{
            .id = id,
            .object_state = object_state_list,
        };
    }

    pub fn run(self: *const @This(), context: *EventRunContext) !void {
        switch (context.graph.level) {
            .hall => |hall| {
                for (self.object_state) |entry| {
                    const object, const state = entry;
                    try hall.setObjectState(object, state);
                }
            },
            else => {},
        }
    }
};

pub const ActionSwitchSection = struct {
    pub const tag = "Share.CActionSwitchSection";
    pub const action_type: i32 = 6;

    id: u32,
    section_id: u32,
    transform_id: []const u8,
    camera_x: u32 = 0,
    camera_y: u32 = 0,

    pub fn run(_: *const @This(), context: *EventRunContext) !void {
        context.interrupt();
    }

    pub fn toProto(self: *const @This(), arena: Allocator) !pb_action.ActionSwitchSection {
        return .{
            .section_id = self.section_id,
            .transform_id = try .copy(self.transform_id, arena),
            .camera_x = self.camera_x,
            .camera_y = self.camera_y,
        };
    }
};
