const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn PropertyPrimitive(comptime T: type) type {
    return struct {
        value: T,
        changed: bool,

        pub fn init(value: T) @This() {
            return .{
                .value = value,
                .changed = false,
            };
        }

        pub fn set(self: *@This(), value: T) void {
            if (self.value != value) {
                self.value = value;
                self.changed = true;
            }
        }

        pub fn isChanged(self: *const @This()) bool {
            return self.changed;
        }

        pub fn reset(self: *@This()) void {
            self.changed = false;
        }
    };
}

pub const PropertyString = struct {
    chars: []const u8,
    allocator: ?Allocator,
    changed: bool,

    pub fn init(chars: []const u8, allocator: ?Allocator) @This() {
        return .{
            .chars = chars,
            .allocator = allocator,
            .changed = false,
        };
    }

    pub fn set(self: *@This(), chars: []const u8, allocator: ?Allocator) @This() {
        if (self.allocator) |old_allocator| {
            old_allocator.free(self.chars);
        }

        self.chars = chars;
        self.allocator = allocator;
        self.changed = true;
    }

    pub fn isChanged(self: *const @This()) bool {
        return self.changed;
    }

    pub fn reset(self: *@This()) void {
        self.changed = false;
    }

    pub const empty: @This() = .{
        .chars = &.{},
        .changed = false,
        .allocator = null,
    };
};

pub fn PropertyHashSet(comptime V: type) type {
    return struct {
        allocator: Allocator,
        internal_map: std.AutoArrayHashMapUnmanaged(V, void),
        added_values: std.ArrayListUnmanaged(V),

        pub fn init(allocator: Allocator) @This() {
            return .{
                .allocator = allocator,
                .internal_map = .empty,
                .added_values = .empty,
            };
        }

        pub fn contains(self: *const @This(), value: V) bool {
            return self.internal_map.contains(value);
        }

        pub fn values(self: *const @This()) []V {
            return self.internal_map.keys();
        }

        pub fn put(self: *@This(), value: V) !void {
            try self.internal_map.put(self.allocator, value, {});
            try self.markAsNew(value);
        }

        pub fn markAsNew(self: *@This(), value: V) !void {
            if (std.mem.indexOfScalar(V, self.added_values.items, value) == null) {
                try self.added_values.append(self.allocator, value);
            }
        }

        pub fn clear(self: *@This()) void {
            self.internal_map.clearAndFree(self.allocator);
            self.added_values.clearAndFree(self.allocator);
        }

        pub fn remove(self: *@This(), value: V) bool {
            const removed = self.internal_map.swapRemove(value);
            if (std.mem.indexOfScalar(V, self.added_values.items, value)) |index| {
                _ = self.added_values.swapRemove(index);
            }

            return removed;
        }

        pub fn isChanged(self: *const @This()) bool {
            return self.added_values.items.len != 0;
        }

        pub fn reset(self: *@This()) void {
            self.added_values.clearRetainingCapacity();
        }

        pub fn deinit(self: *@This()) void {
            self.internal_map.deinit(self.allocator);
            self.added_values.deinit(self.allocator);
        }
    };
}

pub fn PropertyHashMap(comptime K: type, comptime V: type) type {
    return struct {
        allocator: Allocator,
        internal_map: std.AutoArrayHashMapUnmanaged(K, V),
        changed_keys: std.ArrayListUnmanaged(K),

        pub fn init(allocator: Allocator) @This() {
            return .{
                .allocator = allocator,
                .internal_map = .empty,
                .changed_keys = .empty,
            };
        }

        pub fn contains(self: *const @This(), key: K) bool {
            return self.internal_map.contains(key);
        }

        pub fn iterator(self: *const @This()) std.AutoArrayHashMapUnmanaged(K, V).Iterator {
            return self.internal_map.iterator();
        }

        pub fn get(self: *const @This(), key: K) ?V {
            return self.internal_map.get(key);
        }

        pub fn getPtr(self: *@This(), key: K) ?*V {
            const value = self.internal_map.getPtr(key);
            if (value != null) self.markAsChanged(key) catch @panic("out of memory");

            return value;
        }

        pub fn put(self: *@This(), key: K, value: V) !void {
            try self.internal_map.put(self.allocator, key, value);
            try self.markAsChanged(key);
        }

        pub fn markAsChanged(self: *@This(), key: K) !void {
            if (std.mem.indexOfScalar(K, self.changed_keys.items, key) == null) {
                try self.changed_keys.append(self.allocator, key);
            }
        }

        pub fn remove(self: *@This(), key: K) bool {
            const removed = self.internal_map.swapRemove(key);
            if (std.mem.indexOfScalar(K, self.changed_keys.items, key)) |index| {
                _ = self.changed_keys.swapRemove(index);
            }

            return removed;
        }

        pub fn isChanged(self: *const @This()) bool {
            return self.changed_keys.items.len != 0;
        }

        pub fn reset(self: *@This()) void {
            self.changed_keys.clearRetainingCapacity();
        }

        pub fn deinit(self: *@This()) void {
            self.internal_map.deinit(self.allocator);
            self.changed_keys.deinit(self.allocator);
        }
    };
}
