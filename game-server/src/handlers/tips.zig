const std = @import("std");

const NetContext = @import("../net/NetContext.zig");
const protocol = @import("protocol");

pub fn onGetTipsDataCsReq(context: *NetContext, _: protocol.ByName(.GetTipsDataCsReq)) !protocol.ByName(.GetTipsDataScRsp) {
    const data: protocol.ByName(.TipsData) = protocol.makeProto(.TipsData, .{
        .tips = protocol.makeProto(.TipsInfo, .{}, context.arena),
        .fairy = protocol.makeProto(.FairyInfo, .{}, context.arena),
        .loading_page_tips = protocol.makeProto(.LoadingPageTipsInfo, .{}, context.arena),
    }, context.arena);

    return protocol.makeProto(.GetTipsDataScRsp, .{
        .retcode = 0,
        .data = data,
    }, context.arena);
}
