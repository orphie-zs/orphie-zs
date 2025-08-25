const protobuf = @import("protobuf_nap");
const std = @import("std");
const builtin = @import("builtin");

var protobuf_compiler_step: ?*std.Build.Step = null;

pub fn build(b: *std.Build) void {
    const opts = .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    };

    // in order to run protoc on host machine, host target should be passed to compile protoc-gen-zig
    const host_target: std.Build.ResolvedTarget = .{
        .query = .fromTarget(builtin.target),
        .result = builtin.target,
    };

    const protobuf_dep = b.dependency("protobuf_nap", opts);

    if (std.fs.cwd().access("protocol/nap.proto", .{})) {
        const protoc_step = protobuf.RunProtocStep.create(b, protobuf_dep.builder, host_target, .{
            .destination_directory = b.path("protocol/src"),
            .source_files = &.{
                "protocol/nap.proto",
                "protocol/action.proto",
                "protocol/head.proto",
            },
            .include_directories = &.{},
        });

        b.getInstallStep().dependOn(&protoc_step.step);
        protobuf_compiler_step = &protoc_step.step;
    } else |_| {} // don't invoke protoc if proto definition doesn't exist

    registerRunCommand(b, opts, "orphie_dispatch_server", "run-orphie-dispatch", "Build and run the dispatch server");
    registerRunCommand(b, opts, "orphie_game_server", "run-orphie-gameserver", "Build and run the game server");

    const dispatch_dep = b.dependency("orphie_dispatch_server", opts);
    const dispatch_artifact = dispatch_dep.artifact("orphie_dispatch_server");
    const game_dep = b.dependency("orphie_game_server", opts);
    const game_artifact = game_dep.artifact("orphie_game_server");

    if (protobuf_compiler_step) |protoc_step| {
        dispatch_artifact.step.dependOn(protoc_step);
        game_artifact.step.dependOn(protoc_step);
    }

    const dispatch_install = b.addInstallArtifact(dispatch_artifact, .{});
    const game_install = b.addInstallArtifact(game_artifact, .{});

    const dispatch_step = b.step("orphie_dispatch_server", "Build only the dispatch server");
    dispatch_step.dependOn(&dispatch_install.step);

    const game_step = b.step("orphie_game_server", "Build only the game server");
    game_step.dependOn(&game_install.step);

    b.installArtifact(dispatch_artifact);
    b.installArtifact(game_artifact);
}

fn registerRunCommand(
    b: *std.Build,
    opts: anytype,
    artifact_name: []const u8,
    cmd: []const u8,
    description: []const u8,
) void {
    const dep = b.dependency(artifact_name, opts);
    const artifact = dep.artifact(artifact_name);

    if (protobuf_compiler_step) |protoc_step| {
        artifact.step.dependOn(protoc_step);
    }

    const install_step = b.addInstallArtifact(artifact, .{});
    const run_step = b.addRunArtifact(artifact);

    run_step.step.dependOn(&install_step.step);

    if (b.args) |args| {
        run_step.addArgs(args);
    }

    b.step(cmd, description).dependOn(&run_step.step);
}
