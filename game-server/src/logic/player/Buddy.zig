const std = @import("std");
const property = @import("../property.zig");
const protocol = @import("protocol");

const BuddyBaseTemplate = @import("../../data/templates.zig").BuddyBaseTemplate;
const Allocator = std.mem.Allocator;
const ByName = protocol.ByName;

const Self = @This();

pub const BuddySkillType = enum(u32) {
    const count: usize = @typeInfo(@This()).@"enum".fields.len;

    manual = 2,
    passive = 3,
    qte = 4,
    aid = 5,

    pub fn getMaxLevel(self: @This()) u32 {
        return switch (self) {
            .passive => 5,
            inline else => |_| 8,
        };
    }
};

pub const container_field = .buddy_list;

id: u32,
level: u32,
exp: u32,
star: u32,
rank: u32,
is_favorite: bool,
skill_type_level: [BuddySkillType.count]struct { BuddySkillType, u32 },

pub fn init(template: BuddyBaseTemplate) @This() {
    var skill_type_level: [BuddySkillType.count]struct { BuddySkillType, u32 } = undefined;
    inline for (std.meta.fields(BuddySkillType), 0..BuddySkillType.count) |field, i| {
        const skill_type = @field(BuddySkillType, field.name);
        skill_type_level[i] = .{ skill_type, 1 };
    }

    return .{
        .id = @intCast(template.id),
        .level = 60,
        .exp = 0,
        .rank = 6,
        .star = 1,
        .is_favorite = false,
        .skill_type_level = skill_type_level,
    };
}

pub fn toProto(self: *const @This(), allocator: Allocator) !ByName(.BuddyInfo) {
    var proto = protocol.makeProto(.BuddyInfo, .{
        .id = self.id,
        .level = self.level,
        .exp = self.exp,
        .star = self.star,
        .rank = self.rank,
        .is_favorite = self.is_favorite,
    }, allocator);

    for (self.skill_type_level) |entry| {
        const skill_type, const level = entry;

        try protocol.addToList(&proto, .skill_type_level, protocol.makeProto(.BuddySkillLevel, .{
            .skill_type = @intFromEnum(skill_type),
            .level = level,
        }, allocator));
    }

    return proto;
}
