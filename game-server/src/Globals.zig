const std = @import("std");

const TemplateCollection = @import("data/templates.zig").TemplateCollection;
const EventGraphTemplateMap = @import("data/graph/EventGraphTemplateMap.zig");
const Rsa = @import("common").crypto.Rsa;

templates: TemplateCollection,
event_graph_map: EventGraphTemplateMap,
initial_xorpad: []const u8,
rsa: Rsa,
gameplay_settings: GameplaySettings,

pub const GameplaySettings = struct {
    pub const defaults = @embedFile("gameplay_settings.default.zon");

    hadal_entrance_list: []const HadalEntranceConfig,
    avatar_overrides: []const AvatarConfig,
    weapons: []const WeaponConfig,
    equipment: []const EquipConfig,
};

pub const AvatarConfig = struct {
    id: u32,
    level: u32,
    unlocked_talent_num: u32,
    weapon: ?WeaponConfig = null,
    equipment: []const struct { u32, EquipConfig } = &.{},
};

pub const WeaponConfig = struct {
    id: u32,
    level: u32,
    star: u32,
    refine_level: u32,
};

pub const EquipConfig = struct {
    id: u32,
    level: u32,
    star: u32,
    properties: []const struct { u32, u32, u32 },
    sub_properties: []const struct { u32, u32, u32 },
};

pub const HadalEntranceConfig = struct {
    const static_entrances = [_]u32{ 2, 3 };

    entrance_id: u32,
    zone_id: u32,

    pub fn getEntranceType(self: *const @This()) EntranceType {
        return if (std.mem.containsAtLeastScalar(u32, &static_entrances, 1, self.entrance_id)) .constant else .scheduled;
    }

    pub const EntranceType = enum(i32) {
        constant = 1,
        scheduled = 2,
    };
};
