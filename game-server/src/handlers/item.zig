const std = @import("std");

const NetContext = @import("../net/NetContext.zig");
const protocol = @import("protocol");

pub fn onGetWeaponDataCsReq(context: *NetContext, _: protocol.ByName(.GetWeaponDataCsReq)) !protocol.ByName(.GetWeaponDataScRsp) {
    var rsp = protocol.makeProto(.GetWeaponDataScRsp, .{}, context.arena);

    var items = context.session.player_info.?.item_data.item_map.iterator();
    while (items.next()) |entry| {
        try entry.value_ptr.addToProto(&rsp, context.arena);
    }

    return rsp;
}

pub fn onGetEquipDataCsReq(context: *NetContext, _: protocol.ByName(.GetEquipDataCsReq)) !protocol.ByName(.GetEquipDataScRsp) {
    var rsp = protocol.makeProto(.GetEquipDataScRsp, .{}, context.arena);

    var items = context.session.player_info.?.item_data.item_map.iterator();
    while (items.next()) |entry| {
        try entry.value_ptr.addToProto(&rsp, context.arena);
    }

    return rsp;
}

pub fn onGetItemDataCsReq(context: *NetContext, _: protocol.ByName(.GetItemDataCsReq)) !protocol.ByName(.GetItemDataScRsp) {
    var rsp = protocol.makeProto(.GetItemDataScRsp, .{}, context.arena);

    var items = context.session.player_info.?.item_data.item_map.iterator();
    while (items.next()) |entry| {
        try entry.value_ptr.addToProto(&rsp, context.arena);
    }

    return rsp;
}

pub fn onGetWishlistDataCsReq(context: *NetContext, _: protocol.ByName(.GetWishlistDataCsReq)) !protocol.ByName(.GetWishlistDataScRsp) {
    return protocol.makeProto(.GetWishlistDataScRsp, .{}, context.arena);
}
