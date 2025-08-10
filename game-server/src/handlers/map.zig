const std = @import("std");

const NetContext = @import("../net/NetContext.zig");
const protocol = @import("protocol");

pub fn onGetAreaMapDataCsReq(context: *NetContext, _: protocol.ByName(.GetAreaMapDataCsReq)) !protocol.ByName(.GetAreaMapDataScRsp) {
    return protocol.makeProto(.GetAreaMapDataScRsp, .{
        .retcode = 0,
        .data = try context.session.player_info.?.map_data.toProto(context.arena),
    }, context.arena);
}

pub fn onGetNewAreaPortalListCsReq(context: *NetContext, _: protocol.ByName(.GetNewAreaPortalListCsReq)) !protocol.ByName(.GetNewAreaPortalListScRsp) {
    return protocol.makeProto(.GetNewAreaPortalListScRsp, .{
        .retcode = 0,
    }, context.arena);
}

pub fn onUrbanAreaShowCsReq(context: *NetContext, req: protocol.ByName(.UrbanAreaShowCsReq)) !protocol.ByName(.UrbanAreaShowScRsp) {
    if (protocol.getField(req, .area_show_list, std.ArrayList(protocol.ByName(.UrbanAreaShowInfo)))) |area_show_list| {
        const map_data = &context.session.player_info.?.map_data;

        for (area_show_list.items) |info| {
            const area_id = protocol.getField(info, .area_id, u32) orelse continue;
            if (map_data.street.getPtr(area_id)) |street| {
                street.is_area_pop_show |= @intFromBool(protocol.getField(info, .is_area_pop_show, bool) orelse false);
                street.is_3d_area_show |= @intFromBool(protocol.getField(info, .is_3d_area_show, bool) orelse false);
                street.is_urban_area_show |= @intFromBool(protocol.getField(info, .is_urban_area_show, bool) orelse false);
            }
        }
    }

    return protocol.makeProto(.UrbanAreaShowScRsp, .{
        .retcode = 0,
    }, context.arena);
}
