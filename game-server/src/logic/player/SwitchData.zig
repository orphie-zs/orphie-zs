const std = @import("std");
const protocol = @import("protocol");

const ByName = protocol.ByName;
const makeProto = protocol.makeProto;

const PropertyHashSet = @import("../property.zig").PropertyHashSet;
const TemplateCollection = @import("../../data/templates.zig").TemplateCollection;

const Allocator = std.mem.Allocator;
const Self = @This();

open_systems: PropertyHashSet(ClientSystemType),

pub fn init(allocator: Allocator) Self {
    return .{
        .open_systems = .init(allocator),
    };
}

pub fn openAllSystems(self: *Self) !void {
    inline for (std.meta.fields(ClientSystemType)) |field| {
        try self.open_systems.put(@field(ClientSystemType, field.name));
    }
}

pub fn toProto(self: *Self, allocator: Allocator) !ByName(.SwitchData) {
    var proto = makeProto(.SwitchData, .{}, allocator);

    for (self.open_systems.values()) |cst| {
        try protocol.addToList(&proto, .open_system_list, @intFromEnum(cst));
    }

    return proto;
}

pub fn isChanged(self: *const Self) bool {
    inline for (std.meta.fields(Self)) |field| {
        if (@hasDecl(@FieldType(Self, field.name), "isChanged")) {
            if (@field(self, field.name).isChanged()) return true;
        }
    }

    return false;
}

pub fn ackPlayerSync(_: *const Self, _: *protocol.ByName(.PlayerSyncScNotify), _: Allocator) !void {
    // ackPlayerSync.
}

pub fn reset(self: *Self) void {
    inline for (std.meta.fields(Self)) |field| {
        if (@hasDecl(@FieldType(Self, field.name), "reset")) {
            @field(self, field.name).reset();
        }
    }
}

pub fn deinit(self: *Self) void {
    inline for (std.meta.fields(Self)) |field| {
        if (@hasDecl(@FieldType(Self, field.name), "deinit")) {
            @field(self, field.name).deinit();
        }
    }
}

pub const ClientSystemType = enum(u32) {
    client_system_hollow_quest = 0,
    client_system_vhs = 1,
    client_system_role = 2,
    client_system_smithy = 3,
    client_system_package = 4,
    client_system_teleport = 5,
    client_system_interknot = 6,
    client_system_vhs_store = 7,
    client_system_ramen_store = 8,
    client_system_workbench = 9,
    client_system_grocery = 10,
    client_system_viedo_shop = 11,
    client_system_story_mode_switch = 12,
    client_system_qte_switch = 13,
    client_system_lineup_select = 14,
    client_system_use_story_mode = 15,
    client_system_use_manual_qte_mode = 16,
    client_system_newsstand = 17,
    client_system_toy = 18,
    client_system_arcade = 19,
    client_system_tartarus_hounds = 20,
    client_system_gacha = 21,
    client_system_cafe = 22,
    client_system_trash = 23,
    client_system_battle_daily = 24,
    client_system_buddy = 25,
    client_system_buddy_install = 26,
    client_system_activity = 27,
    client_system_abyss = 28,
    client_system_abyss_heat = 29,
    client_system_arcade_room = 30,
    client_system_arcade_game = 31,
    client_system_train = 32,
    client_system_avatar_base = 33,
    client_system_avatar_equip = 34,
    client_system_land_revive = 35,
    client_system_double_elite = 36,
    client_system_boss_small = 37,
    client_system_boss_big = 38,
    client_system_hia = 39,
    client_system_monster_card = 40,
    client_system_daily_quest = 41,
    client_system_rally = 42,
    client_system_hadal = 43,
    client_system_photowall = 44,
    client_system_abyss_collect = 45,
    client_system_abyss_shop_01 = 46,
    client_system_hadal_shop = 47,
    client_system_activity_pv = 48,
    client_system_photo_activity = 49,
    client_system_overlord_feast_store = 50,
    client_system_overlord_feast_settlement = 51,
    client_system_set_time = 52,
    client_system_activity_battle_arpg = 53,
    client_system_activity_battle_act = 54,
    client_system_weekly_bingo = 55,
    client_system_3z = 56,
    client_system_collection_cabinet = 57,
    client_system_food_truck = 58,
    client_system_flower_shop = 59,
    client_system_temple = 60,
    client_system_temple_hive_box = 61,
    client_system_temple_good_goods = 62,
    client_system_temple_devon_pawn_shop = 63,
    client_system_temple_yum_cha_sin = 64,
    client_system_player_skin_accessory = 65,
};
