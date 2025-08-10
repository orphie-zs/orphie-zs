const std = @import("std");
const templates = @import("../../data/templates.zig");
const protocol = @import("protocol");

const Avatar = @import("../player/Avatar.zig");

const ItemData = @import("../player/ItemData.zig");
const Weapon = ItemData.Weapon;
const Equip = ItemData.Equip;

const Allocator = std.mem.Allocator;
const HashMap = std.AutoArrayHashMapUnmanaged;
const TemplateCollection = templates.TemplateCollection;
const AvatarBattleTemplate = templates.AvatarBattleTemplate;
const AvatarLevelAdvanceTemplate = templates.AvatarLevelAdvanceTemplate;
const AvatarPassiveSkillTemplate = templates.AvatarPassiveSkillTemplate;
const WeaponTemplate = templates.WeaponTemplate;
const WeaponLevelTemplate = templates.WeaponLevelTemplate;
const WeaponStarTemplate = templates.WeaponStarTemplate;

const Self = @This();

avatar_id: u32,
properties: HashMap(PropertyType, i32),
allocator: Allocator,

pub fn init(
    avatar: *const Avatar,
    weapon: ?*const Weapon,
    equipment: []const ?*const Equip,
    tmpl: *const TemplateCollection,
    allocator: Allocator,
) !Self {
    var self = Self{
        .avatar_id = avatar.id,
        .properties = .empty,
        .allocator = allocator,
    };

    const battle_template = tmpl.getConfigByKey(.avatar_battle_template_tb, @as(i32, @intCast(avatar.id))) orelse return error.MissingBattleTemplate;
    try self.initBaseProperties(battle_template);

    const level_advance_template = tmpl.getAvatarLevelAdvanceTemplate(avatar.id, avatar.rank) orelse return error.MissingLevelAdvanceTemplate;
    try self.initLevelAdvanceProperties(&level_advance_template);

    try self.growPropertyByLevel(avatar.level, PropertyType.HpMaxBase, PropertyType.HpMaxGrowth, PropertyType.HpMaxAdvance);
    try self.growPropertyByLevel(avatar.level, PropertyType.AtkBase, PropertyType.AtkGrowth, PropertyType.AtkAdvance);
    try self.growPropertyByLevel(avatar.level, PropertyType.DefBase, PropertyType.DefGrowth, PropertyType.DefAdvance);

    if (tmpl.getAvatarPassiveSkillTemplate(avatar.id, avatar.passive_skill_level)) |passive_skill_template| {
        try self.applyPassiveSkillProperties(passive_skill_template);
    }

    if (weapon) |info| {
        const weapon_template = tmpl.getConfigByKey(.weapon_template_tb, @as(i32, @intCast(info.id))) orelse return error.MissingWeaponTemplate;
        const rarity: u32 = @mod(@divFloor(info.id, 1000), 10);

        const level_template = tmpl.getWeaponLevelTemplate(rarity, info.level) orelse return error.MissingWeaponLevelTemplate;
        const star_template = tmpl.getWeaponStarTemplate(rarity, info.star) orelse return error.MissingWeaponStarTemplate;

        try self.initWeaponProperties(weapon_template, &level_template, &star_template);
    }

    try self.initEquipmentProperties(equipment, tmpl);
    try self.initEquipmentSuitProperties(equipment, tmpl);

    try self.setDynamicProperties();
    try self.applyCoreSkillBonus(avatar.skill_type_level[@intFromEnum(Avatar.AvatarSkillType.core_skill)]);
    self.clearCustomProperties();

    try self.setBattleProperties();
    return self;
}

pub fn deinit(self: *Self) void {
    self.properties.deinit(self.allocator);
}

pub fn toProto(self: *const Self, allocator: Allocator) !protocol.ByName(.AvatarUnitInfo) {
    var info = protocol.makeProto(.AvatarUnitInfo, .{
        .avatar_id = self.avatar_id,
    }, allocator);

    var properties = self.properties.iterator();
    while (properties.next()) |entry| {
        try protocol.addToMap(&info, .properties, @intFromEnum(entry.key_ptr.*), entry.value_ptr.*);
    }

    return info;
}

// TODO: find out where this is actually configured
const core_skill_specials = [_]struct { u32, PropertyType, PropertyType, [7]i32 }{
    .{ 1121, PropertyType.Atk, PropertyType.Def, .{ 40, 46, 52, 60, 66, 72, 80 } },
    .{ 1371, PropertyType.SkipDefAtk, PropertyType.HpMax, .{ 10, 10, 10, 10, 10, 10, 10 } },
};

fn applyCoreSkillBonus(self: *Self, level: u32) !void {
    inline for (core_skill_specials) |bonus| {
        const avatar_id, const bonus_prop, const scale_prop, const percentage = bonus;
        if (avatar_id == self.avatar_id) {
            const bonus_value = @divFloor(self.getProperty(scale_prop) * percentage[level - 1], 100);
            try self.modifyProperty(bonus_prop, bonus_value);
        }
    }
}

fn initEquipmentSuitProperties(self: *Self, equipment: []const ?*const Equip, tmpl: *const TemplateCollection) !void {
    var suit_times: [Avatar.equipment_num]struct { u32, u32 } = undefined;
    var suit_count: usize = 0;

    for (equipment) |item| {
        if (item) |equip| {
            const suit_id = ((equip.id / 100) * 100);
            for (suit_times[0..suit_count]) |*entry| {
                if (entry.@"0" == suit_id) {
                    entry.@"1" += 1;
                    break;
                }
            } else {
                suit_times[suit_count] = .{ suit_id, 1 };
                suit_count += 1;
            }
        }
    }

    for (suit_times[0..suit_count]) |suit| {
        const suit_id, const count = suit;
        if (tmpl.getConfigByKey(.equipment_suit_template_tb, @as(i32, @intCast(suit_id)))) |suit_template| {
            if (count >= suit_template.primary_condition) {
                for (0..suit_template.primary_suit_propertys_value.len) |i| {
                    const key: u32 = @intCast(suit_template.primary_suit_propertys_property[i]);
                    const value = suit_template.primary_suit_propertys_value[i];

                    const property = std.meta.intToEnum(PropertyType, key) catch {
                        std.log.debug("initEquipmentSuitProperties: invalid property {} in suit {}", .{ key, suit_id });
                        continue;
                    };

                    try self.modifyProperty(property, value);
                }
            }
        }
    }
}

fn initEquipmentProperties(self: *Self, equipment: []const ?*const Equip, tmpl: *const TemplateCollection) !void {
    const divisor: f32 = 10_000;

    for (equipment) |item| {
        if (item) |equip| {
            const rarity: u32 = (equip.id / 10) % 10;
            const level_template = tmpl.getEquipmentLevelTemplate(rarity, equip.level);
            const rate: f32 = if (level_template) |template| @floatFromInt(template.property_rate) else 1;

            for (equip.properties) |prop| {
                if (prop) |property| {
                    const key = std.meta.intToEnum(PropertyType, property.key) catch {
                        std.log.debug("initEquipmentProperties: invalid property {} in equip {}", .{ property.key, equip.id });
                        continue;
                    };

                    const base: f32 = @floatFromInt(property.base_value);
                    const value: i32 = @intFromFloat(base + (base * rate / divisor));
                    try self.modifyProperty(key, value);
                }
            }

            for (equip.sub_properties) |prop| {
                if (prop) |property| {
                    const key = std.meta.intToEnum(PropertyType, property.key) catch {
                        std.log.debug("initEquipmentProperties: invalid sub_property {} in equip {}", .{ property.key, equip.id });
                        continue;
                    };

                    const base: f32 = @floatFromInt(property.base_value);
                    const add: f32 = @floatFromInt(property.add_value);
                    try self.modifyProperty(key, @intFromFloat(base * add));
                }
            }
        }
    }
}

fn initWeaponProperties(self: *Self, weapon: *const WeaponTemplate, level: *const WeaponLevelTemplate, star: *const WeaponStarTemplate) !void {
    const divisor: f32 = 10_000;

    const level_rate: f32 = @floatFromInt(level.rate);
    const star_rate: f32 = @floatFromInt(star.star_rate);
    const rand_rate: f32 = @floatFromInt(star.rand_rate);

    const base_property_base_value: f32 = @floatFromInt(weapon.base_property_value);
    const base_property_level_rate: i32 = @intFromFloat((base_property_base_value * level_rate) / divisor);
    const base_property_star_rate: i32 = @intFromFloat((base_property_base_value * star_rate) / divisor);

    if (std.meta.intToEnum(PropertyType, @as(u32, @intCast(weapon.base_property_property))) catch null) |base_property| {
        try self.modifyProperty(base_property, @as(i32, @intFromFloat(base_property_base_value)) + base_property_level_rate + base_property_star_rate);
    } else {
        std.log.err("weapon base property is invalid: {} (weapon_id: {})", .{ weapon.base_property_property, weapon.id });
    }

    const rand_property_base_value: f32 = @floatFromInt(weapon.rand_property_value);
    const rand_property_rate: i32 = @intFromFloat((rand_property_base_value * rand_rate) / divisor);

    if (std.meta.intToEnum(PropertyType, @as(u32, @intCast(weapon.rand_property_property))) catch null) |rand_property| {
        try self.modifyProperty(rand_property, @as(i32, @intFromFloat(rand_property_base_value)) + rand_property_rate);
    } else {
        std.log.err("weapon rand property is invalid: {} (weapon_id: {})", .{ weapon.rand_property_property, weapon.id });
    }
}

fn setBattleProperties(self: *Self) !void {
    try self.modifyProperty(PropertyType.SkipDefAtk, @divFloor(self.getProperty(PropertyType.Atk) * 30, 100));

    // Set *Battle variations of properties.
    try self.setProperty(PropertyType.HpMaxBattle, self.getProperty(PropertyType.HpMax));
    try self.setProperty(PropertyType.AtkBattle, self.getProperty(PropertyType.Atk));
    try self.setProperty(PropertyType.BreakStunBattle, self.getProperty(PropertyType.BreakStun));
    try self.setProperty(PropertyType.SkipDefAtkBattle, self.getProperty(PropertyType.SkipDefAtk));
    try self.setProperty(PropertyType.DefBattle, self.getProperty(PropertyType.Def));
    try self.setProperty(PropertyType.CritBattle, self.getProperty(PropertyType.Crit));
    try self.setProperty(PropertyType.CritDmgBattle, self.getProperty(PropertyType.CritDmg));
    try self.setProperty(PropertyType.SpRecoverBattle, self.getProperty(PropertyType.SpRecover));
    try self.setProperty(PropertyType.ElementMysteryBattle, self.getProperty(PropertyType.ElementMystery));
    try self.setProperty(PropertyType.ElementAbnormalPowerBattle, self.getProperty(PropertyType.ElementAbnormalPower));
    try self.setProperty(PropertyType.AddedDamageRatioBattle, self.getProperty(PropertyType.AddedDamageRatio));
    try self.setProperty(PropertyType.AddedDamageRatioPhysicsBattle, self.getProperty(PropertyType.AddedDamageRatioPhysics));
    try self.setProperty(PropertyType.AddedDamageRatioFireBattle, self.getProperty(PropertyType.AddedDamageRatioFire));
    try self.setProperty(PropertyType.AddedDamageRatioIceBattle, self.getProperty(PropertyType.AddedDamageRatioIce));
    try self.setProperty(PropertyType.AddedDamageRatioElecBattle, self.getProperty(PropertyType.AddedDamageRatioElec));
    try self.setProperty(PropertyType.AddedDamageRatioEtherBattle, self.getProperty(PropertyType.AddedDamageRatioEther));
    try self.setProperty(PropertyType.RpRecoverBattle, self.getProperty(PropertyType.RpRecover));
    try self.setProperty(PropertyType.SkipDefDamageRatioBattle, self.getProperty(PropertyType.SkipDefDamageRatio));
    try self.modifyProperty(PropertyType.PenRatioBattle, self.getProperty(PropertyType.Pen));
    try self.modifyProperty(PropertyType.PenDeltaBattle, self.getProperty(PropertyType.PenValue));

    // Set current HP
    try self.modifyProperty(PropertyType.Hp, self.getProperty(PropertyType.HpMax));
}

fn setDynamicProperties(self: *Self) !void {
    try self.setDynamicProperty(PropertyType.HpMax, PropertyType.HpMaxBase, PropertyType.HpMaxRatio, PropertyType.HpMaxDelta);
    try self.setDynamicProperty(PropertyType.SpMax, PropertyType.SpMaxBase, PropertyType.None, PropertyType.SpMaxDelta);
    try self.setDynamicProperty(PropertyType.Atk, PropertyType.AtkBase, PropertyType.AtkRatio, PropertyType.AtkDelta);
    try self.setDynamicProperty(PropertyType.BreakStun, PropertyType.BreakStunBase, PropertyType.BreakStunRatio, PropertyType.BreakStunDelta);
    try self.setDynamicProperty(PropertyType.SkipDefAtk, PropertyType.SkipDefAtkBase, PropertyType.None, PropertyType.SkipDefAtkDelta);
    try self.setDynamicProperty(PropertyType.Def, PropertyType.DefBase, PropertyType.DefRatio, PropertyType.DefDelta);
    try self.setDynamicProperty(PropertyType.Crit, PropertyType.CritBase, PropertyType.None, PropertyType.CritDelta);
    try self.setDynamicProperty(PropertyType.CritDmg, PropertyType.CritDmgBase, PropertyType.None, PropertyType.CritDmgDelta);
    try self.setDynamicProperty(PropertyType.Pen, PropertyType.PenBase, PropertyType.None, PropertyType.PenDelta);
    try self.setDynamicProperty(PropertyType.PenValue, PropertyType.PenValueBase, PropertyType.None, PropertyType.PenValueDelta);
    try self.setDynamicProperty(PropertyType.SpRecover, PropertyType.SpRecoverBase, PropertyType.SpRecoverRatio, PropertyType.SpRecoverDelta);
    try self.setDynamicProperty(PropertyType.RpRecover, PropertyType.RpRecoverBase, PropertyType.RpRecoverRatio, PropertyType.RpRecoverDelta);
    try self.setDynamicProperty(PropertyType.ElementMystery, PropertyType.ElementMysteryBase, PropertyType.None, PropertyType.ElementMysteryDelta);
    try self.setDynamicProperty(PropertyType.ElementAbnormalPower, PropertyType.ElementAbnormalPowerBase, PropertyType.ElementAbnormalPowerRatio, PropertyType.ElementAbnormalPowerDelta);
    try self.setDynamicProperty(PropertyType.AddedDamageRatio, PropertyType.AddedDamageRatio1, PropertyType.None, PropertyType.AddedDamageRatio3);
    try self.setDynamicProperty(PropertyType.AddedDamageRatioPhysics, PropertyType.AddedDamageRatioPhysics1, PropertyType.None, PropertyType.AddedDamageRatioPhysics3);
    try self.setDynamicProperty(PropertyType.AddedDamageRatioFire, PropertyType.AddedDamageRatioFire1, PropertyType.None, PropertyType.AddedDamageRatioFire3);
    try self.setDynamicProperty(PropertyType.AddedDamageRatioIce, PropertyType.AddedDamageRatioIce1, PropertyType.None, PropertyType.AddedDamageRatioIce3);
    try self.setDynamicProperty(PropertyType.AddedDamageRatioElec, PropertyType.AddedDamageRatioElec1, PropertyType.None, PropertyType.AddedDamageRatioElec3);
    try self.setDynamicProperty(PropertyType.AddedDamageRatioEther, PropertyType.AddedDamageRatioEther1, PropertyType.None, PropertyType.AddedDamageRatioEther3);
    try self.setDynamicProperty(PropertyType.SkipDefDamageRatio, PropertyType.SkipDefDamageRatio1, PropertyType.None, PropertyType.SkipDefDamageRatio3);
}

fn setDynamicProperty(self: *Self, prop: PropertyType, base_prop: PropertyType, ratio_prop: PropertyType, delta_prop: PropertyType) !void {
    const divisor: f32 = 10_000.0;

    const base = self.getProperty(base_prop);
    const delta = self.getProperty(delta_prop);

    const base_float: f32 = @floatFromInt(base);
    const ratio: f32 = @floatFromInt(self.getProperty(ratio_prop));

    var scaled_base = (base_float * ratio) / divisor;
    if (prop == PropertyType.HpMax) {
        scaled_base = @ceil(scaled_base);
    }

    try self.setProperty(prop, base + @as(i32, @intFromFloat(scaled_base)) + delta);
}

fn applyPassiveSkillProperties(self: *Self, template: *const AvatarPassiveSkillTemplate) !void {
    for (0..template.propertys_property.len) |i| {
        const property: u32 = @intCast(template.propertys_property[i]);
        const value = template.propertys_number[i];

        const key = std.meta.intToEnum(PropertyType, property) catch {
            std.log.err("invalid property type encountered: {}", .{property});
            continue;
        };

        try self.modifyProperty(key, value);
    }
}

fn growPropertyByLevel(self: *Self, level: u32, base_prop: PropertyType, growth_prop: PropertyType, advance_prop: PropertyType) !void {
    const divisor: f32 = 10_000.0;

    const base = self.properties.get(base_prop).?;
    const advance = self.properties.get(advance_prop).?;
    const growth: f32 = @floatFromInt(self.properties.get(growth_prop).?);
    const level_float: f32 = @floatFromInt(level - 1);

    const add: i32 = @intFromFloat((level_float * growth) / divisor);
    try self.setProperty(base_prop, base + add + advance);
}

fn initLevelAdvanceProperties(self: *Self, template: *const AvatarLevelAdvanceTemplate) !void {
    try self.setProperty(PropertyType.HpMaxAdvance, template.hp_max);
    try self.setProperty(PropertyType.AtkAdvance, template.attack);
    try self.setProperty(PropertyType.DefAdvance, template.defence);
}

fn initBaseProperties(self: *Self, template: *const AvatarBattleTemplate) !void {
    try self.setProperty(PropertyType.HpMaxBase, template.hp_max);
    try self.setProperty(PropertyType.HpMaxGrowth, template.health_growth);
    try self.setProperty(PropertyType.AtkBase, template.attack);
    try self.setProperty(PropertyType.AtkGrowth, template.attack_growth);
    try self.setProperty(PropertyType.BreakStunBase, template.break_stun);
    try self.setProperty(PropertyType.DefBase, template.defence);
    try self.setProperty(PropertyType.DefGrowth, template.defence_growth);
    try self.setProperty(PropertyType.CritBase, template.crit);
    try self.setProperty(PropertyType.CritDmgBase, template.crit_damage);
    try self.setProperty(PropertyType.PenBase, 0);
    try self.setProperty(PropertyType.PenValueBase, 0);
    try self.setProperty(PropertyType.SpMaxBase, template.sp_bar_point);
    try self.setProperty(PropertyType.SpRecoverBase, template.sp_recover);
    try self.setProperty(PropertyType.ElementMysteryBase, template.element_mystery);
    try self.setProperty(PropertyType.ElementAbnormalPowerBase, template.element_abnormal_power);
    try self.setProperty(PropertyType.RpMax, template.rp_max);
    try self.setProperty(PropertyType.RpRecoverBase, template.rp_recover);
}

fn modifyProperty(self: *Self, key: PropertyType, delta: i32) !void {
    const current = self.properties.get(key) orelse 0;
    try self.setProperty(key, current + delta);
}

fn setProperty(self: *Self, key: PropertyType, value: i32) !void {
    try self.properties.put(self.allocator, key, value);
}

fn getProperty(self: *Self, key: PropertyType) i32 {
    return self.properties.get(key) orelse 0;
}

fn clearCustomProperties(self: *Self) void {
    _ = self.properties.swapRemove(PropertyType.HpMaxGrowth);
    _ = self.properties.swapRemove(PropertyType.AtkGrowth);
    _ = self.properties.swapRemove(PropertyType.DefGrowth);
    _ = self.properties.swapRemove(PropertyType.HpMaxAdvance);
    _ = self.properties.swapRemove(PropertyType.AtkAdvance);
    _ = self.properties.swapRemove(PropertyType.DefAdvance);
}

pub const PropertyType = enum(u32) {
    None = 0,
    Hp = 1,
    HpMax = 111,
    SpMax = 115,
    RpMax = 119,
    Atk = 121,
    BreakStun = 122,
    SkipDefAtk = 123,
    Def = 131,
    Crit = 201,
    CritDmg = 211,
    Pen = 231,
    PenValue = 232,
    SpRecover = 305,
    AddedDamageRatio = 307,
    ElementMystery = 312,
    ElementAbnormalPower = 314,
    AddedDamageRatioPhysics = 315,
    AddedDamageRatioFire = 316,
    AddedDamageRatioIce = 317,
    AddedDamageRatioElec = 318,
    AddedDamageRatioEther = 319,
    RpRecover = 320,
    SkipDefDamageRatio = 322,
    // battle
    HpMaxBattle = 1111,
    AtkBattle = 1121,
    BreakStunBattle = 1122,
    SkipDefAtkBattle = 1123,
    DefBattle = 1131,
    CritBattle = 1201,
    CritDmgBattle = 1211,
    PenRatioBattle = 1231,
    PenDeltaBattle = 1232,
    SpRecoverBattle = 1305,
    AddedDamageRatioBattle = 1307,
    ElementMysteryBattle = 1312,
    ElementAbnormalPowerBattle = 1314,
    AddedDamageRatioPhysicsBattle = 1315,
    AddedDamageRatioFireBattle = 1316,
    AddedDamageRatioIceBattle = 1317,
    AddedDamageRatioElecBattle = 1318,
    AddedDamageRatioEtherBattle = 1319,
    RpRecoverBattle = 1320,
    SkipDefDamageRatioBattle = 1322,
    // base
    HpMaxBase = 11101,
    SpMaxBase = 11501,
    AtkBase = 12101,
    BreakStunBase = 12201,
    SkipDefAtkBase = 12301, // ?? client has 12205 for some reason
    DefBase = 13101,
    CritBase = 20101,
    CritDmgBase = 21101,
    PenBase = 23101,
    PenValueBase = 23201,
    SpRecoverBase = 30501,
    ElementMysteryBase = 31201,
    ElementAbnormalPowerBase = 31401,
    RpRecoverBase = 32001,
    // ratio
    HpMaxRatio = 11102,
    AtkRatio = 12102,
    BreakStunRatio = 12202,
    DefRatio = 13102,
    SpRecoverRatio = 30502,
    ElementAbnormalPowerRatio = 31402,
    RpRecoverRatio = 32002,
    // delta
    HpMaxDelta = 11103,
    SpMaxDelta = 11503,
    AtkDelta = 12103,
    BreakStunDelta = 12203,
    SkipDefAtkDelta = 12303, // ?? client has 12205 for some reason
    DefDelta = 13103,
    CritDelta = 20103,
    CritDmgDelta = 21103,
    PenDelta = 23103,
    PenValueDelta = 23203,
    SpRecoverDelta = 30503,
    ElementMysteryDelta = 31203,
    ElementAbnormalPowerDelta = 31403,
    RpRecoverDelta = 32003,
    // damage ratios 1/3
    AddedDamageRatio1 = 30701,
    AddedDamageRatio3 = 30703,
    AddedDamageRatioPhysics1 = 31501,
    AddedDamageRatioPhysics3 = 31503,
    AddedDamageRatioFire1 = 31601,
    AddedDamageRatioFire3 = 31603,
    AddedDamageRatioIce1 = 31701,
    AddedDamageRatioIce3 = 31703,
    AddedDamageRatioElec1 = 31801,
    AddedDamageRatioElec3 = 31803,
    AddedDamageRatioEther1 = 31901,
    AddedDamageRatioEther3 = 31903,
    SkipDefDamageRatio1 = 32201,
    SkipDefDamageRatio3 = 32203,
    // --- custom
    // growth
    HpMaxGrowth = 99991110,
    AtkGrowth = 99991210,
    DefGrowth = 99991310,
    // advance
    HpMaxAdvance = 99991111,
    AtkAdvance = 99991211,
    DefAdvance = 99991311,
};
