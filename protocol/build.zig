const std = @import("std");

pub fn build(b: *std.Build) void {
    const options = .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    };

    const protobuf = b.dependency("protobuf_nap", options);

    const module = b.addModule("protocol", .{
        .root_source_file = b.path("src/root.zig"),
        .target = options.target,
        .optimize = options.optimize,
    });

    module.addImport("protobuf", protobuf.module("protobuf"));
}
