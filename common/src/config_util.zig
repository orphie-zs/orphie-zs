const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn loadOrCreate(ty: anytype, path: []const u8, gpa: Allocator, arena: Allocator) !ty {
    const content = std.fs.cwd().readFileAllocOptions(gpa, path, 1024 * 1024, null, @alignOf(u8), 0) catch {
        return try createAt(ty, path, arena);
    };

    defer gpa.free(content);
    return try std.zon.parse.fromSlice(ty, arena, content, null, .{});
}

fn createAt(ty: anytype, path: []const u8, arena: std.mem.Allocator) !ty {
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    try file.writeAll(ty.defaults);
    return try std.zon.parse.fromSlice(ty, arena, ty.defaults, null, .{});
}
