const std = @import("std");

pub fn build(b: *std.Build) !void {
    const options = .{
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    };

    const common = b.dependency("common", options);
    const protocol = b.dependency("protocol", options);
    const network = b.dependency("network", options);

    const exe = b.addExecutable(.{
        .name = "orphie_game_server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = options.target,
            .optimize = options.optimize,
        }),
    });

    const filecfg_dir = std.fs.cwd().openDir("assets/Filecfg/", .{ .iterate = true }) catch @panic("assets/Filecfg directory doesn't exist");
    var walker = try filecfg_dir.walk(b.allocator);
    defer walker.deinit();

    while (true) {
        const entry = walker.next() catch break orelse break;
        if (entry.kind == .file) {
            const path = std.mem.concat(b.allocator, u8, &.{ "../assets/Filecfg/", entry.path }) catch @panic("Out of Memory");

            exe.root_module.addAnonymousImport(entry.path, .{
                .root_source_file = b.path(path),
            });
        }
    }

    exe.root_module.addImport("common", common.module("common"));
    exe.root_module.addImport("protocol", protocol.module("protocol"));
    exe.root_module.addImport("network", network.module("network"));
    b.installArtifact(exe);
}
