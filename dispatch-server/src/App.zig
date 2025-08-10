const log = @import("std").log;
const httpz = @import("httpz");
const Config = @import("Config.zig");
const Rsa = @import("common").crypto.Rsa;

const Self = @This();

config: Config,
rsa: Rsa,

pub fn notFound(_: *Self, req: *httpz.Request, res: *httpz.Response) !void {
    if (req.method != .HEAD) {
        log.warn("unhandled request: {s} {s}", .{ @tagName(req.method), req.url.path });
    }

    res.status = 599;
    res.body = "599 Service Unavailable";
}
