const App = @import("App.zig");
const ServerListConfig = @import("Config.zig").ServerListConfig;
const Rsa = @import("common").crypto.Rsa;

const std = @import("std");
const httpz = @import("httpz");

const log = std.log;
const StringKeyValue = httpz.key_value.StringKeyValue;
const Base64Encoder = std.base64.standard.Encoder;

pub const path = "/query_gateway";

pub fn handle(app: *App, req: *httpz.Request, rsp: *httpz.Response) !void {
    const query = try req.query();
    const params = Params.extract(query) catch |err| {
        log.warn("query_gateway: failed to extract parameters: {}", .{err});
        try rsp.json(.{ .retcode = 70 }, .{});
        return;
    };

    log.info("query_gateway: {}", .{params});

    const server_config = for (app.config.server_list) |config| {
        if (config.sid == app.config.bound_sid and std.mem.eql(u8, config.bound_version, params.version)) {
            break config;
        }
    } else {
        log.warn("query_gateway: no bound server for version {s}", .{params.version});
        try rsp.json(.{ .retcode = 71 }, .{});
        return;
    };

    const res = &app.config.res;
    const data = ServerDispatchData{
        .retcode = 0,
        .title = server_config.title,
        .region_name = server_config.name,
        .gateway = .{
            .ip = server_config.gateway_ip,
            .port = server_config.gateway_port,
        },
        .client_secret_key = app.config.client_secret_key,
        .cdn_check_url = res.cdn_check_url,
        .cdn_conf_ext = .{
            .game_res = .{
                .res_revision = res.res_revision,
                .audio_revision = res.res_revision,
                .base_url = res.res_base_url,
                .branch = res.branch,
                .md5_files = res.res_md5_files,
            },
            .design_data = .{
                .data_revision = res.data_revision,
                .base_url = res.data_base_url,
                .md5_files = res.data_md5_files,
            },
            .silence_data = .{
                .silence_revision = res.silence_revision,
                .base_url = res.silence_base_url,
                .md5_files = res.silence_md5_files,
            },
        },
        .region_ext = .{
            .func_switch = .{
                .is_kcp = 1,
                .enable_operation_log = 1,
                .enable_performance_log = 1,
            },
        },
    };

    const data_json = try std.json.stringifyAlloc(rsp.arena, &data, .{});

    const content = try rsp.arena.alloc(u8, app.rsa.paddedLength(data_json.len));
    app.rsa.encrypt(data_json, content);

    var sign: [Rsa.SignSize]u8 = undefined;
    app.rsa.sign(data_json, &sign);

    const content_b64 = try rsp.arena.alloc(u8, Base64Encoder.calcSize(content.len));
    const sign_b64 = try rsp.arena.alloc(u8, Base64Encoder.calcSize(sign.len));

    _ = Base64Encoder.encode(content_b64, content);
    _ = Base64Encoder.encode(sign_b64, &sign);

    try rsp.json(.{ .content = content_b64, .sign = sign_b64 }, .{});
}

const Params = struct {
    version: []const u8,
    seed: []const u8,
    rsa_ver: u32,

    fn extract(query: *StringKeyValue) !Params {
        const max_allowed_version_length = 64;
        const version = query.get("version") orelse return error.MissingVersion;
        if (version.len > max_allowed_version_length) return error.TooLongVersionString;

        const seed = query.get("seed") orelse return error.MissingSeed;
        const rsa_ver_str = query.get("rsa_ver") orelse return error.MissingRsaVer;
        const rsa_ver = std.fmt.parseInt(u32, rsa_ver_str, 10) catch return error.RsaVerNotAnInteger;

        return .{
            .version = version,
            .seed = seed,
            .rsa_ver = rsa_ver,
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

        try writer.print("(version: {s}, seed: {s}, rsa_ver: {})", .{
            self.version,
            self.seed,
            self.rsa_ver,
        });
    }
};

const ServerGateway = struct {
    ip: []const u8,
    port: u16,
};

const CdnGameRes = struct {
    base_url: []const u8,
    res_revision: []const u8,
    audio_revision: []const u8,
    branch: []const u8,
    md5_files: []const u8,
};

const CdnDesignData = struct {
    base_url: []const u8,
    data_revision: []const u8,
    md5_files: []const u8,
};

const CdnSilenceData = struct {
    base_url: []const u8,
    silence_revision: []const u8,
    md5_files: []const u8,
};

const CdnConfExt = struct {
    game_res: CdnGameRes,
    design_data: CdnDesignData,
    silence_data: CdnSilenceData,
};

const RegionSwitchFunc = packed struct {
    enable_performance_log: u1,
    enable_operation_log: u1,
    is_kcp: u1,

    pub fn jsonStringify(self: @This(), jws: anytype) !void {
        try jws.beginObject();
        try jws.objectField("enablePerformanceLog");
        try jws.write(self.enable_performance_log);
        try jws.objectField("enableOperationLog");
        try jws.write(self.enable_operation_log);
        try jws.objectField("isKcp");
        try jws.write(self.is_kcp);
        try jws.endObject();
    }
};

const RegionExtension = struct {
    func_switch: RegionSwitchFunc,
};

const ServerDispatchData = struct {
    retcode: i32,
    title: []const u8,
    region_name: []const u8,
    client_secret_key: []const u8,
    cdn_check_url: []const u8,
    gateway: ServerGateway,
    cdn_conf_ext: CdnConfExt,
    region_ext: RegionExtension,
};
