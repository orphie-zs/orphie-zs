const std = @import("std");

const StringMap = std.StaticStringMap;
const HashMap = std.AutoArrayHashMapUnmanaged;
const Allocator = std.mem.Allocator;
const ConfigEventAction = @import("ConfigEventAction.zig");

pub const SectionEventGraphConfig = struct {
    pub const event_reference_lists: []const []const u8 = &.{ "on_add", "on_enter", "on_exit" };

    id: u32,
    on_add: []const u32,
    on_enter: []const u32,
    on_exit: []const u32,
    events: HashMap(u32, ConfigEvent),
};

pub const NpcEventGraphConfig = struct {
    pub const on_interact_event_name = "OnInteract";

    id: u32,
    on_interact_event_id: ?u32,
    event_name_map: StringMap(u32),
    events: HashMap(u32, ConfigEvent),
};

pub const ConfigEvent = struct {
    const json_attribute_id = "id";
    const json_attribute_actions = "actions";

    id: u32,
    actions: []const ?ConfigEventAction,

    pub fn getActionById(self: @This(), action_id: u32) ?*const ConfigEventAction {
        for (self.actions) |*action| {
            if (action.*) |*config| if (config.getId() == action_id) return config;
        } else {
            return null;
        }
    }

    pub fn parseFromJsonObject(json_object: std.json.ObjectMap, name: []const u8, arena: Allocator) !ConfigEvent {
        const event_id: u32 = @intCast((json_object.get(json_attribute_id) orelse return error.MissingEventID).integer);
        const actions = (json_object.get(json_attribute_actions) orelse return error.MissingActionList).array;
        const config_actions = try arena.alloc(?ConfigEventAction, actions.items.len);

        for (actions.items, 0..actions.items.len) |action, i| {
            const event_action = ConfigEventAction.fromJson(action, arena) catch |err| {
                if (err == error.UnknownActionType) {
                    const action_type = (action.object.get(ConfigEventAction.json_attribute_type) orelse return error.MissingActionType).string;
                    std.log.warn("skipping unknown action type '{s}' in event '{s}'", .{ action_type, name });
                    config_actions[i] = null;
                    continue;
                }

                return err;
            };

            config_actions[i] = event_action;
        }

        return .{
            .id = event_id,
            .actions = config_actions,
        };
    }
};
