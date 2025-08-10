const std = @import("std");

const NetContext = @import("../net/NetContext.zig");
const protocol = @import("protocol");

pub fn onGetBuddyDataCsReq(context: *NetContext, _: protocol.ByName(.GetBuddyDataCsReq)) !protocol.ByName(.GetBuddyDataScRsp) {
    return protocol.makeProto(.GetBuddyDataScRsp, .{ .retcode = 0 }, context.arena);
}
