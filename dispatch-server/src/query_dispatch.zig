const App = @import("App.zig");
const std = @import("std");
const httpz = @import("httpz");
const log = std.log;
const StringKeyValue = httpz.key_value.StringKeyValue;

pub const path = "/query_dispatch";

pub fn handle(app: *App, req: *httpz.Request, rsp: *httpz.Response) !void {
    const query = try req.query();
    const params = Params.extract(query) catch |err| {
        log.warn("query_dispatch: failed to extract parameters: {}", .{err});
        try rsp.json(QueryDispatchRes{
            .retcode = 70,
        }, .{});
        return;
    };

    log.info("query_dispatch: {}", .{params});

    var bound_server_count: usize = 0;
    for (app.config.server_list) |config| {
        if (std.mem.eql(u8, config.bound_version, params.version)) {
            bound_server_count += 1;
        }
    }

    var region_list = try rsp.arena.alloc(ServerListInfo, bound_server_count);
    var i: usize = 0;
    for (app.config.server_list) |config| {
        if (std.mem.eql(u8, config.bound_version, params.version)) {
            region_list[i] = .{
                .retcode = 0,
                .biz = "nap_global",
                .name = config.name,
                .title = config.title,
                .dispatch_url = config.dispatch_url,
                .ping_url = config.ping_url,
                .env = 2,
                .area = 2,
                .is_recommend = true,
            };
            i += 1;
        }
    }

    try rsp.json(QueryDispatchRes{
        .retcode = 0,
        .region_list = region_list,
    }, .{});
}

const Params = struct {
    version: []const u8,

    fn extract(query: *StringKeyValue) !Params {
        const max_allowed_version_length = 64;
        const version = query.get("version") orelse return error.MissingVersion;
        if (version.len > max_allowed_version_length) return error.TooLongVersionString;

        return .{
            .version = version,
        };
    }

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("(version: {s})", .{self.version});
    }
};

const QueryDispatchRes = struct {
    retcode: i32,
    region_list: []const ServerListInfo = &.{},
};

const ServerListInfo = struct {
    retcode: i32,
    name: []const u8,
    title: []const u8,
    biz: []const u8,
    dispatch_url: []const u8,
    ping_url: []const u8,
    env: u8,
    area: u8,
    is_recommend: bool,
};
