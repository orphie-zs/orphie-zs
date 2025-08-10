const std = @import("std");

pub fn build(b: *std.Build) void {
    const options = .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    };

    const httpz = b.dependency("httpz", options);
    const common = b.dependency("common", options);

    const exe = b.addExecutable(.{
        .name = "orphie_dispatch_server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = options.target,
            .optimize = options.optimize,
        }),
    });

    exe.root_module.addImport("httpz", httpz.module("httpz"));
    exe.root_module.addImport("common", common.module("common"));
    b.installArtifact(exe);
}
