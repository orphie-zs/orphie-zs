const std = @import("std");
const tsv = @import("tsv.zig");
const TsvTable = @import("table.zig").TsvTable;
const TemplateTb = tsv.TemplateTb;

const ArenaAllocator = std.heap.ArenaAllocator;

pub const AvatarBaseTemplate = TsvTable("AvatarBaseTemplateTb.tsv");
pub const AvatarBattleTemplate = TsvTable("AvatarBattleTemplateTb.tsv");
pub const AvatarLevelAdvanceTemplate = TsvTable("AvatarLevelAdvanceTemplateTb.tsv");
pub const AvatarPassiveSkillTemplate = TsvTable("AvatarPassiveSkillTemplateTb.tsv");
pub const AvatarSkinBaseTemplate = TsvTable("AvatarSkinBaseTemplateTb.tsv");
pub const WeaponTemplate = TsvTable("WeaponTemplateTb.tsv");
pub const WeaponLevelTemplate = TsvTable("WeaponLevelTemplateTb.tsv");
pub const WeaponStarTemplate = TsvTable("WeaponStarTemplateTb.tsv");
pub const EquipmentTemplate = TsvTable("EquipmentTemplateTb.tsv");
pub const EquipmentSuitTemplate = TsvTable("EquipmentSuitTemplateTb.tsv");
pub const EquipmentLevelTemplate = TsvTable("EquipmentLevelTemplateTb.tsv");
pub const UnlockConfigTemplate = TsvTable("UnlockConfigTemplateTb.tsv");
pub const TeleportConfigTemplate = TsvTable("TeleportConfigTemplateTb.tsv");
pub const PostGirlConfigTemplate = TsvTable("PostGirlConfigTemplateTb.tsv");
pub const MainCityObjectTemplate = TsvTable("MainCityObjectTemplateTb.tsv");
pub const UrbanAreaMapTemplate = TsvTable("UrbanAreaMapTemplateTb.tsv");
pub const UrbanAreaMapGroupTemplate = TsvTable("UrbanAreaMapGroupTemplateTb.tsv");
pub const ZoneInfoTemplate = TsvTable("ZoneInfoTemplateTb.tsv");
pub const LayerInfoTemplate = TsvTable("LayerInfoTemplateTb.tsv");
pub const HadalZoneQuestTemplate = TsvTable("HadalZoneQuestTemplateTb.tsv");

pub const TemplateCollection = struct {
    const max_file_size = 8192 * 1024;
    const Self = @This();

    arena: ArenaAllocator,
    avatar_base_template_tb: TemplateTb(AvatarBaseTemplate, .id),
    avatar_battle_template_tb: TemplateTb(AvatarBattleTemplate, .id),
    avatar_level_advance_template_tb: TemplateTb(AvatarLevelAdvanceTemplate, .avatar_id),
    avatar_passive_skill_template_tb: TemplateTb(AvatarPassiveSkillTemplate, .skill_id),
    avatar_skin_base_template_tb: TemplateTb(AvatarSkinBaseTemplate, .id),
    weapon_template_tb: TemplateTb(WeaponTemplate, .id),
    weapon_level_template_tb: TemplateTb(WeaponLevelTemplate, .level),
    weapon_star_template_tb: TemplateTb(WeaponStarTemplate, .star),
    equipment_template_tb: TemplateTb(EquipmentTemplate, .item_id),
    equipment_suit_template_tb: TemplateTb(EquipmentSuitTemplate, .id),
    equipment_level_template_tb: TemplateTb(EquipmentLevelTemplate, .level),
    unlock_config_template_tb: TemplateTb(UnlockConfigTemplate, .id),
    teleport_config_template_tb: TemplateTb(TeleportConfigTemplate, .teleport_id),
    post_girl_config_template_tb: TemplateTb(PostGirlConfigTemplate, .id),
    main_city_object_template_tb: TemplateTb(MainCityObjectTemplate, .tag_id),
    urban_area_map_template_tb: TemplateTb(UrbanAreaMapTemplate, .area_id),
    urban_area_map_group_template_tb: TemplateTb(UrbanAreaMapGroupTemplate, .area_group_id),
    zone_info_template_tb: TemplateTb(ZoneInfoTemplate, .zone_id),
    layer_info_template_tb: TemplateTb(LayerInfoTemplate, .layer_id),
    hadal_zone_quest_template_tb: TemplateTb(HadalZoneQuestTemplate, .layer_id),

    pub fn load(gpa: std.mem.Allocator) !Self {
        var collection: Self = undefined;
        collection.arena = ArenaAllocator.init(gpa);

        @setEvalBranchQuota(1_000_000);
        inline for (std.meta.fields(Self)) |field| {
            if (field.type == ArenaAllocator) continue;

            const content = try std.fs.cwd().readFileAllocOptions(gpa, comptime getTsvPath(field.type), max_file_size, null, @alignOf(u8), 0);
            defer gpa.free(content);

            @field(collection, field.name) = try tsv.parseFromSlice(field.type, content, collection.arena.allocator());
        }

        return collection;
    }

    pub fn getConfigByKey(self: *const Self, field: anytype, key: anytype) ?*const std.meta.Elem(@FieldType(@FieldType(Self, @tagName(field)), "items")) {
        const template_tb = @field(self, @tagName(field));
        const key_map = @field(template_tb, tsv.keyMapName(@TypeOf(template_tb)));
        const index = key_map.get(key) orelse return null;

        return &template_tb.items[index];
    }

    pub fn getAvatarLevelAdvanceTemplate(self: *const Self, avatar_id: u32, advance_id: u32) ?AvatarLevelAdvanceTemplate {
        for (self.avatar_level_advance_template_tb.items) |template| {
            if (template.avatar_id == @as(i32, @intCast(avatar_id)) and template.id == @as(i32, @intCast(advance_id))) {
                return template;
            }
        }

        return null;
    }

    pub fn getAvatarPassiveSkillTemplate(self: *const Self, avatar_id: u32, passive_skill_level: u32) ?*const AvatarPassiveSkillTemplate {
        const skill_id: i32 = @intCast(avatar_id * 1000 + passive_skill_level);
        return self.getConfigByKey(.avatar_passive_skill_template_tb, skill_id);
    }

    pub fn getWeaponLevelTemplate(self: *const Self, rarity: u32, level: u32) ?WeaponLevelTemplate {
        for (self.weapon_level_template_tb.items) |template| {
            if (template.rarity == @as(i32, @intCast(rarity)) and template.level == @as(i32, @intCast(level))) {
                return template;
            }
        }

        return null;
    }

    pub fn getWeaponStarTemplate(self: *const Self, rarity: u32, star: u32) ?WeaponStarTemplate {
        for (self.weapon_star_template_tb.items) |template| {
            if (template.rarity == @as(i32, @intCast(rarity)) and template.star == @as(i32, @intCast(star))) {
                return template;
            }
        }

        return null;
    }

    pub fn getEquipmentLevelTemplate(self: *const Self, rarity: u32, level: u32) ?EquipmentLevelTemplate {
        for (self.equipment_level_template_tb.items) |template| {
            if (template.rarity == @as(i32, @intCast(rarity)) and template.level == @as(i32, @intCast(level))) {
                return template;
            }
        }

        return null;
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }
};

fn getTsvPath(comptime Table: type) []const u8 {
    const type_name = @typeName(Table);
    const start_index = std.mem.indexOfScalar(u8, type_name, '"').? + 1;
    const end_index = std.mem.indexOfScalar(u8, type_name[start_index..type_name.len], '"').?;
    const file_name = type_name[start_index .. start_index + end_index];
    return "assets/Filecfg/" ++ file_name;
}
