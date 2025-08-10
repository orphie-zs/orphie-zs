const std = @import("std");
const Transform = @import("../math/Transform.zig");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const StringMap = std.StringHashMapUnmanaged;

const Self = @This();

const default_section_id: u32 = 2;
const default_transform_id: []const u8 = "Workshop_PlayerPos_Default";

allocator: Allocator,
section_id: u32,
last_transform_id: []const u8,
position: ?Transform,
lift_map_arena: ArenaAllocator,
lift_status_map: StringMap(u32),

pub fn init(allocator: Allocator) !Self {
    return .{
        .allocator = allocator,
        .section_id = default_section_id,
        .last_transform_id = try allocator.dupe(u8, default_transform_id),
        .position = null,
        .lift_map_arena = ArenaAllocator.init(allocator),
        .lift_status_map = .empty,
    };
}

pub fn deinit(self: *Self) void {
    self.lift_map_arena.deinit();
    self.allocator.free(self.last_transform_id);
}

pub fn savePosition(self: *Self, position: []const f64, rotation: []const f64) void {
    self.position = .{
        .position = .{ position[0], position[1], position[2] },
        .rotation = .{ rotation[0], rotation[1], rotation[2] },
    };
}

pub fn switchSection(self: *Self, section_id: u32, transform_id: []const u8) !void {
    self.allocator.free(self.last_transform_id);

    self.section_id = section_id;
    self.last_transform_id = try self.allocator.dupe(u8, transform_id);
    self.position = null;

    _ = self.lift_map_arena.reset(.free_all);
    self.lift_status_map = .empty;
}

pub fn setLiftStatus(self: *Self, name: []const u8, status: u32) !void {
    if (self.lift_status_map.getPtr(name)) |value| {
        value.* = status;
    } else {
        const arena = self.lift_map_arena.allocator();

        const key = try arena.dupe(u8, name);
        try self.lift_status_map.put(arena, key, status);
    }
}
