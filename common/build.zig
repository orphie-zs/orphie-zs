const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.addModule("common", .{
        .root_source_file = b.path("src/root.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });
}
