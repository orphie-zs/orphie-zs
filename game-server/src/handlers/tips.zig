const std = @import("std");

const NetContext = @import("../net/NetContext.zig");
const protocol = @import("protocol");

pub fn onGetTipsDataCsReq(context: *NetContext, _: protocol.ByName(.GetTipsDataCsReq)) !protocol.ByName(.GetTipsDataScRsp) {
    return protocol.makeProto(.GetTipsDataScRsp, .{
        .retcode = 0,
        .data = try context.session.player_info.?.tips_info.toProto(context.arena),
    }, context.arena);
}
