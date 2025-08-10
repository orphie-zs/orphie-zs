const std = @import("std");
const protocol = @import("protocol");
const ByName = protocol.ByName;
const Allocator = std.mem.Allocator;

pub const HallScene = @import("scene/HallScene.zig");
pub const FightScene = @import("scene/FightScene.zig");
pub const HadalZoneScene = @import("scene/HadalZoneScene.zig");

pub const SceneType = enum(u32) {
    hall = 1,
    fight = 3,
    hadal_zone = 9,
};

pub const LocalPlayType = enum(u32) {
    mini_scape_battle = 228,
    daily_challenge = 206,
    summer_surfing = 297,
    hadal_zone_alivecount = 222,
    side_scrolling_captain = 241,
    rally_long_fight = 207,
    big_boss_battle_longfight = 217,
    pure_hollow_battle_longhfight = 281,
    bangboo_royale = 240,
    guide_special = 203,
    hadal_zone = 209,
    hadal_zone_bosschallenge = 224,
    archive_long_fight = 212,
    archive_battle = 201,
    activity_combat_pause = 230,
    smash_bro = 242,
    operation_team_coop = 219,
    boss_nest_hard_battle = 220,
    unkown = 0,
    avatar_demo_trial = 213,
    babel_tower = 223,
    dual_elite = 208,
    mp_big_boss_battle = 214,
    pure_hollow_battle_hardmode = 282,
    boss_rush_battle = 218,
    chess_board_battle = 202,
    map_challenge_battle = 291,
    pure_hollow_battle = 280,
    coin_brushing_battle = 231,
    training_root_tactics = 292,
    big_boss_battle = 211,
    bangboo_autobattle = 295,
    mini_scape_short_battle = 229,
    boss_little_battle_longfight = 215,
    bangboo_dream_rogue_battle = 293,
    training_room = 290,
    s2_rogue_battle = 226,
    operation_beta_demo = 216,
    mechboo_battle = 296,
    chess_board_longfihgt_battle = 204,
    target_shooting_battle = 294,
    buddy_towerdefense_battle = 227,
    summer_shooting = 298,
    boss_battle = 210,
    level_zero = 205,
    side_scrolling_thegun_battle = 221,
};

pub const Scene = union(SceneType) {
    hall: *HallScene,
    fight: *FightScene,
    hadal_zone: *HadalZoneScene,

    pub fn toProto(self: @This(), allocator: Allocator) !ByName(.SceneData) {
        return switch (self) {
            inline else => |scene| try scene.toProto(allocator),
        };
    }

    pub fn deinit(self: @This()) void {
        return switch (self) {
            inline else => |scene| scene.destroy(),
        };
    }
};
