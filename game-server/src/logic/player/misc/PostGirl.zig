const std = @import("std");
const property = @import("../../property.zig");
const property_util = @import("../../property_util.zig");
const protocol = @import("protocol");

const Allocator = std.mem.Allocator;
const PropertyHashSet = property.PropertyHashSet;
const PropertyPrimitive = property.PropertyPrimitive;
const ByName = protocol.ByName;

const Self = @This();

unlocked_post_girl: PropertyHashSet(u32),
show_post_girl: PropertyHashSet(u32),
random_toggle: PropertyPrimitive(bool),

pub fn init(allocator: Allocator) Self {
    return .{
        .unlocked_post_girl = .init(allocator),
        .show_post_girl = .init(allocator),
        .random_toggle = .init(false),
    };
}

pub fn deinit(self: *Self) void {
    self.unlocked_post_girl.deinit();
    self.show_post_girl.deinit();
}

pub fn toProto(self: *const Self, misc_data: *ByName(.MiscData), allocator: Allocator) !void {
    var proto = protocol.makeProto(.PostGirlInfo, .{}, allocator);

    for (self.unlocked_post_girl.values()) |id| {
        try protocol.addToList(&proto, .post_girl_item_list, protocol.makeProto(.PostGirlItem, .{
            .id = id,
            .unlock_time = 1000,
        }, allocator));
    }

    for (self.show_post_girl.values()) |id| {
        try protocol.addToList(&proto, .show_post_girl_id_list, id);
    }

    protocol.setFields(&proto, .{ .post_girl_random_toggle = self.random_toggle.value });

    protocol.setFields(misc_data, .{ .post_girl = proto });
}

pub fn isChanged(self: *const Self) bool {
    return property_util.isChanged(self);
}

pub fn ackSync(self: *const Self, misc_sync: *ByName(.MiscSync), allocator: Allocator) !void {
    var proto = protocol.makeProto(.PostGirlSync, .{}, allocator);

    for (self.show_post_girl.values()) |id| {
        try protocol.addToList(&proto, .new_post_girl_item_list, protocol.makeProto(.PostGirlItem, .{
            .id = id,
            .unlock_time = 1000,
        }, allocator));
    }

    for (self.show_post_girl.values()) |id| {
        try protocol.addToList(&proto, .show_post_girl_id_list, id);
    }

    protocol.setFields(&proto, .{ .post_girl_random_toggle = self.random_toggle.value });

    protocol.setFields(misc_sync, .{ .post_girl = proto });
}

pub fn reset(self: *Self) void {
    self.unlocked_post_girl.reset();
    self.show_post_girl.reset();
}
