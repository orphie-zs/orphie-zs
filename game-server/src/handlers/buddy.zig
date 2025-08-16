const std = @import("std");

const NetContext = @import("../net/NetContext.zig");
const protocol = @import("protocol");

pub fn onGetBuddyDataCsReq(context: *NetContext, _: protocol.ByName(.GetBuddyDataCsReq)) !protocol.ByName(.GetBuddyDataScRsp) {
    var rsp = protocol.makeProto(.GetBuddyDataScRsp, .{}, context.arena);

    var items = context.session.player_info.?.item_data.item_map.iterator();

    while (items.next()) |entry| {
        switch (entry.value_ptr.*) {
            .buddy => |buddy| try protocol.addToList(&rsp, .buddy_list, try buddy.toProto(context.arena)),
            else => |_| {},
        }
    }

    return rsp;
}
