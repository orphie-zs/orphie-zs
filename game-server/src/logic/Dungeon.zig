const std = @import("std");
const protocol = @import("protocol");

const TemplateCollection = @import("../data/templates.zig").TemplateCollection;
const AvatarUnit = @import("battle/AvatarUnit.zig");
const PlayerInfo = @import("player/PlayerInfo.zig");
const Avatar = @import("player/Avatar.zig");
const ItemData = @import("player/ItemData.zig");

const Allocator = std.mem.Allocator;
const ByName = protocol.ByName;
const Self = @This();

allocator: Allocator,
quest_id: u32 = 0,
quest_type: u32 = 0,
begin_time: i64,
player: *PlayerInfo,
templates: *const TemplateCollection,
avatar_units: std.ArrayListUnmanaged(AvatarUnit),
package_items: std.ArrayListUnmanaged(PackageItem),

pub fn init(player: *PlayerInfo, templates: *const TemplateCollection, allocator: Allocator) Self {
    return .{
        .allocator = allocator,
        .player = player,
        .templates = templates,
        .begin_time = std.time.timestamp(),
        .avatar_units = .empty,
        .package_items = .empty,
    };
}

pub fn deinit(self: *Self) void {
    for (self.avatar_units.items) |*unit| {
        unit.deinit();
    }

    self.avatar_units.deinit(self.allocator);
    self.package_items.deinit(self.allocator);
}

pub fn setDungeonQuest(self: *Self, quest_type: u32, quest_id: u32) void {
    self.quest_id = quest_id;
    self.quest_type = quest_type;
}

pub fn addAvatarFighter(self: *Self, id: u32, package: PackageType) !void {
    if (package != PackageType.player) {
        std.log.err("dungeon-scoped items are not supported yet", .{});
        return;
    }

    if (self.player.item_data.getItemAs(Avatar, id)) |avatar| {
        try self.package_items.append(self.allocator, .{ .player = id });
        var weapon: ?*const ItemData.Weapon = null;
        var equipment: [Avatar.equipment_num]?*const ItemData.Equip = [_]?*const ItemData.Equip{null} ** Avatar.equipment_num;

        if (avatar.cur_weapon_uid != 0) {
            if (self.player.item_data.getItemPtrAs(ItemData.Weapon, avatar.cur_weapon_uid)) |data| {
                try self.package_items.append(self.allocator, .{ .player = avatar.cur_weapon_uid });
                weapon = data;
            }
        }

        for (avatar.dressed_equip, 0..avatar.dressed_equip.len) |item, i| {
            if (item) |uid| {
                if (self.player.item_data.getItemPtrAs(ItemData.Equip, uid)) |data| {
                    try self.package_items.append(self.allocator, .{ .player = uid });
                    equipment[i] = data;
                }
            }
        }

        const avatar_unit = try AvatarUnit.init(&avatar, weapon, &equipment, self.templates, self.allocator);
        try self.avatar_units.append(self.allocator, avatar_unit);
    } else {
        return error.AvatarNotUnlocked;
    }
}

pub fn toProto(self: *const Self, allocator: Allocator) !ByName(.DungeonInfo) {
    var proto = protocol.makeProto(.DungeonInfo, .{
        .quest_id = self.quest_id,
        .quest_type = self.quest_type,
        .begin_time = self.begin_time,
    }, allocator);

    var package = protocol.makeProto(.DungeonPackageInfo, .{}, allocator);

    for (self.package_items.items) |package_item| {
        switch (package_item) {
            .fight => |item| try item.addToProto(&package, allocator),
            .player => |uid| {
                if (self.player.item_data.item_map.get(uid)) |item| {
                    try item.addToProto(&package, allocator);
                }
            },
        }
    }

    for (self.avatar_units.items) |unit| {
        try protocol.addToList(&proto, .avatar_list, try unit.toProto(allocator));
    }

    protocol.setFields(&proto, .{ .dungeon_package_info = package });
    return proto;
}

pub const PackageType = enum(u32) {
    fight = 1,
    // rogue_like = 2,
    player = 3,
    // dungeon_avatar = 4,
};

pub const PackageItem = union(PackageType) {
    fight: ItemData.Item, // item instance itself, dungeon-scoped
    player: u32, // item id reference from player's persistent storage
};
