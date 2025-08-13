const std = @import("std");
const property = @import("../property.zig");
const protocol = @import("protocol");
const templates = @import("../../data/templates.zig");
const Avatar = @import("Avatar.zig");

const PropertyHashMap = property.PropertyHashMap;
const Allocator = std.mem.Allocator;
const ByName = protocol.ByName;

const AvatarTemplateConfiguration = templates.AvatarTemplateConfiguration;
const WeaponTemplate = templates.WeaponTemplate;

const Self = @This();

const first_unique_id: u32 = 1 << 24;

allocator: Allocator,
item_uid_counter: u32,
item_map: PropertyHashMap(u32, Item),

pub fn init(allocator: Allocator) Self {
    return .{
        .allocator = allocator,
        .item_uid_counter = first_unique_id,
        .item_map = .init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.item_map.deinit();
}

pub fn getItemAs(self: *Self, comptime T: type, uid: u32) ?T {
    if (self.item_map.internal_map.get(uid)) |ptr| {
        switch (ptr) {
            inline else => |item| {
                if (@TypeOf(item) == T) {
                    return item;
                } else {
                    return null;
                }
            },
        }
    } else {
        return null;
    }
}

pub fn getItemPtrAs(self: *Self, comptime T: type, uid: u32) ?*T {
    if (self.item_map.internal_map.getPtr(uid)) |ptr| {
        switch (ptr.*) {
            inline else => |*item| {
                if (std.meta.Child(@TypeOf(item)) == T) {
                    self.item_map.markAsChanged(uid) catch @panic("markAsChanged: out of memory");
                    return item;
                } else {
                    return null;
                }
            },
        }
    } else {
        return null;
    }
}

pub fn addCurrency(self: *Self, id: u32, amount: u32) !void {
    const current = self.getItemCount(id);

    try self.item_map.put(id, .{ .currency = .{
        .id = id,
        .count = current + @as(i32, @intCast(amount)),
    } });
}

pub fn unlockAvatar(self: *Self, config: AvatarTemplateConfiguration) !void {
    if (config.base_template.camp == 0) return error.AvatarIsNotUnlockable;

    const id: u32 = @intCast(config.base_template.id);
    if (self.item_map.contains(id)) {
        return error.AvatarAlreadyUnlocked;
    }

    try self.item_map.put(id, .{ .avatar = Avatar.init(config) });
}

pub fn unlockSkin(self: *Self, id: u32) !void {
    try self.item_map.put(id, .{ .dress = .{ .id = id } });
}

pub fn getItemCount(self: *Self, id: u32) i32 {
    if (self.item_map.get(id)) |item| {
        switch (item) {
            inline else => |data| {
                return if (@hasField(@TypeOf(data), "count")) @field(data, "count") else 1;
            },
        }
    } else {
        return 0;
    }
}

pub fn addWeapon(self: *Self, template: WeaponTemplate) !void {
    const uid = self.nextUid();

    try self.item_map.put(uid, .{ .weapon = .{
        .id = @intCast(template.id),
        .uid = uid,
        .level = 60,
        .exp = 0,
        .star = @intCast(template.star_limit + 1),
        .refine_level = @intCast(template.refine_limit),
        .lock = false,
    } });
}

pub fn nextUid(self: *Self) u32 {
    self.item_uid_counter += 1;
    return self.item_uid_counter;
}

pub fn isChanged(self: *const Self) bool {
    return self.item_map.isChanged();
}

pub fn ackPlayerSync(self: *const Self, notify: *ByName(.PlayerSyncScNotify), allocator: Allocator) !void {
    var avatar_sync = protocol.makeProto(.AvatarSync, .{}, allocator);
    var item_sync = protocol.makeProto(.ItemSync, .{}, allocator);

    for (self.item_map.changed_keys.items) |changed_key| {
        if (self.item_map.get(changed_key)) |item| {
            switch (item) {
                .avatar => |avatar| try protocol.addToList(&avatar_sync, .avatar_list, try avatar.toProto(allocator)),
                else => |_| try item.addToProto(&item_sync, allocator),
            }
        }
    }

    protocol.setFields(notify, .{
        .avatar = avatar_sync,
        .item = item_sync,
    });
}

pub fn reset(self: *Self) void {
    self.item_map.reset();
}

pub const Weapon = struct {
    pub const container_field = .weapon_list;

    id: u32,
    uid: u32,
    level: u32,
    exp: u32,
    star: u32,
    refine_level: u32,
    lock: bool,

    pub fn toProto(self: *const @This(), allocator: Allocator) !ByName(.WeaponInfo) {
        return protocol.makeProto(.WeaponInfo, .{
            .id = self.id,
            .uid = self.uid,
            .level = self.level,
            .exp = self.exp,
            .star = self.star,
            .refine_level = self.refine_level,
            .lock = self.lock,
        }, allocator);
    }
};

pub const Equip = struct {
    pub const container_field = .equip_list;
    pub const main_property_count: usize = 1;
    pub const sub_property_count: usize = 4;

    id: u32,
    uid: u32,
    level: u32,
    exp: u32,
    star: u32,
    properties: [main_property_count]?Property,
    sub_properties: [sub_property_count]?Property,

    pub const Property = struct {
        key: u32,
        base_value: u32,
        add_value: u32,
    };

    pub fn toProto(self: *const @This(), allocator: Allocator) !ByName(.EquipInfo) {
        var proto = protocol.makeProto(.EquipInfo, .{
            .id = self.id,
            .uid = self.uid,
            .level = self.level,
            .exp = self.exp,
            .star = self.star,
        }, allocator);

        for (self.properties) |equip_prop| {
            if (equip_prop) |prop| {
                const prop_proto = protocol.makeProto(.EquipProperty, .{
                    .key = prop.key,
                    .base_value = prop.base_value,
                    .add_value = prop.add_value,
                }, allocator);

                try protocol.addToList(&proto, .propertys, prop_proto);
            }
        }

        for (self.sub_properties) |equip_prop| {
            if (equip_prop) |prop| {
                const prop_proto = protocol.makeProto(.EquipProperty, .{
                    .key = prop.key,
                    .base_value = prop.base_value,
                    .add_value = prop.add_value,
                }, allocator);

                try protocol.addToList(&proto, .sub_propertys, prop_proto);
            }
        }

        return proto;
    }
};

pub const Dress = struct {
    pub const container_field = .item_list;

    id: u32,

    pub fn toProto(self: *const @This(), allocator: Allocator) !ByName(.ItemInfo) {
        return makeItemInfo(self.id, 1, allocator);
    }
};

pub const Currency = struct {
    pub const container_field = .item_list;

    id: u32,
    count: i32,

    pub fn toProto(self: *const @This(), allocator: Allocator) !ByName(.ItemInfo) {
        return makeItemInfo(self.id, self.count, allocator);
    }
};

fn makeItemInfo(id: u32, count: i32, allocator: Allocator) ByName(.ItemInfo) {
    return protocol.makeProto(.ItemInfo, .{
        .id = id,
        .count = count,
    }, allocator);
}

pub const ItemType = enum(u32) {
    currency,
    avatar,
    weapon,
    equip,
    dress,
};

pub const Item = union(ItemType) {
    currency: Currency,
    avatar: Avatar,
    weapon: Weapon,
    equip: Equip,
    dress: Dress,

    pub fn addToProto(self: *const @This(), container: anytype, allocator: Allocator) !void {
        switch (self.*) {
            inline else => |item| {
                const T = @TypeOf(item);
                if (@hasField(std.meta.Child(@TypeOf(container)), @tagName(@field(T, "container_field")))) {
                    const proto = try item.toProto(allocator);
                    try protocol.addToList(container, @field(T, "container_field"), proto);
                }
            },
        }
    }
};
