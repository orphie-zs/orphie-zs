const protobuf = @import("protobuf_nap");
const std = @import("std");

var protobuf_compiler_step: ?*std.Build.Step = null;

pub fn build(b: *std.Build) void {
    const opts = .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    };

    const protobuf_dep = b.dependency("protobuf_nap", opts);

    if (std.fs.cwd().access("protocol/nap.proto", .{})) {
        const protoc_step = protobuf.RunProtocStep.create(b, protobuf_dep.builder, opts.target, .{
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
