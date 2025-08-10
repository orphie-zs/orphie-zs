const std = @import("std");
const common = @import("common");
const network = @import("network");

const gateway = @import("net/gateway.zig");
const Config = @import("Config.zig");
const Globals = @import("Globals.zig");
const TemplateCollection = @import("data/templates.zig").TemplateCollection;

const EventGraphTemplateMap = @import("data/graph/EventGraphTemplateMap.zig");
const graph_loader = @import("data/graph/graph_loader.zig");

const log = std.log;
const Rsa = common.crypto.Rsa;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const std_options: std.Options = .{
    // keep debug logs even in release builds for now
    .log_level = .debug,
};

pub fn main() !void {
    // TODO: use SmpAllocator for release builds.
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(debug_allocator.deinit() == .ok);

    _ = try std.io.getStdOut().write(
        \\         ____             __    _   _____  _____
        \\        / __ \_________  / /_  (_)_/__  / / ___/
        \\       / / / / ___/ __ \/ __ \/ / _ \/ /  \__ \ 
        \\      / /_/ / /  / /_/ / / / / /  __/ /_____/ / 
        \\      \____/_/  / .___/_/ /_/_/\___/____/____/  
        \\               /_/                              
        \\
    );

    const allocator = debug_allocator.allocator();

    var config_arena = ArenaAllocator.init(allocator);
    defer config_arena.deinit();

    const config = try common.config_util.loadOrCreate(Config, "gameserver_config.zon", allocator, config_arena.allocator());
    const gameplay_settings = try common.config_util.loadOrCreate(Globals.GameplaySettings, "gameplay_settings.zon", allocator, config_arena.allocator());

    const xorpad = try config.getXorpad();

    var templates = try TemplateCollection.load(allocator);
    defer templates.deinit();

    var event_graph_map = try graph_loader.loadTemplateMap(allocator);
    defer event_graph_map.deinit();

    const client_public_key_der = config.clientPublicKeyDer(allocator) catch return error.InvalidClientPublicKey;
    const server_private_key_der = config.serverPrivateKeyDer(allocator) catch return error.InvalidServerPrivateKey;

    const rsa = try Rsa.init(client_public_key_der, server_private_key_der);
    allocator.free(client_public_key_der);
    allocator.free(server_private_key_der);

    const globals = Globals{
        .templates = templates,
        .event_graph_map = event_graph_map,
        .rsa = rsa,
        .initial_xorpad = &xorpad,
        .gameplay_settings = gameplay_settings,
    };

    gateway.listen(allocator, config.udp_addr, config.udp_port, config.shutdown_on_disconnect, &globals) catch |err| {
        log.err("failed to initialize gateway: {}", .{err});
        return err;
    };
}
