const std = @import("std");
const property = @import("../../property.zig");
const protocol = @import("protocol");
const UnlockConfigTemplate = @import("../../../data/templates.zig").UnlockConfigTemplate;

const Allocator = std.mem.Allocator;
const PropertyHashSet = property.PropertyHashSet;
const ByName = protocol.ByName;

const Self = @This();

unlocked_id: PropertyHashSet(i32),

pub fn init(allocator: Allocator) Self {
    return .{ .unlocked_id = .init(allocator) };
}

pub fn deinit(self: *Self) void {
    self.unlocked_id.deinit();
}

pub fn unlock(self: *Self, config: UnlockConfigTemplate) !void {
    try self.unlocked_id.put(@intCast(config.id));
}

pub fn toProto(self: *const Self, misc_data: *ByName(.MiscData), allocator: Allocator) !void {
    var proto = protocol.makeProto(.UnlockInfo, .{}, allocator);

    for (self.unlocked_id.values()) |id| {
        try protocol.addToList(&proto, .unlocked_list, id);
    }

    protocol.setFields(misc_data, .{ .unlock = proto });
}
