const std = @import("std");
const httpz = @import("httpz");
const common = @import("common");

const App = @import("App.zig");
const Config = @import("Config.zig");

const query_dispatch = @import("query_dispatch.zig");
const query_gateway = @import("query_gateway.zig");

const log = std.log;
const Rsa = common.crypto.Rsa;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const std_options: std.Options = .{
    // keep debug logs even in release builds for now
    .log_level = .debug,
};

pub fn main() !void {
    var debug_allocator = std.heap.DebugAllocator(.{}){};
    defer _ = debug_allocator.deinit();

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

    const config = try common.config_util.loadOrCreate(Config, "dispatch_config.zon", allocator, config_arena.allocator());

    const client_public_key_der = config.clientPublicKeyDer(allocator) catch |err| {
        log.err("client public key is invalid: {}", .{err});
        return err;
    };

    const server_private_key_der = config.serverPrivateKeyDer(allocator) catch |err| {
        log.err("server private key is invalid: {}", .{err});
        return err;
    };

    const rsa = try Rsa.init(client_public_key_der, server_private_key_der);
    allocator.free(client_public_key_der);
    allocator.free(server_private_key_der);

    var app = App{ .rsa = rsa, .config = config };

    var server = try httpz.Server(*App).init(allocator, .{
        .address = config.http_addr,
        .port = config.http_port,
    }, &app);

    defer {
        server.stop();
        server.deinit();
    }

    var router = try server.router(.{});
    router.get(query_dispatch.path, query_dispatch.handle, .{});
    router.get(query_gateway.path, query_gateway.handle, .{});

    log.info("dispatch server is listening at {s}:{}", .{ config.http_addr, config.http_port });
    try server.listen();
}
