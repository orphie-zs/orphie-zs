const std = @import("std");

const NetContext = @import("../net/NetContext.zig");
const protocol = @import("protocol");

pub fn onVideoGetInfoCsReq(context: *NetContext, _: protocol.ByName(.VideoGetInfoCsReq)) !protocol.ByName(.VideoGetInfoScRsp) {
    return protocol.makeProto(.VideoGetInfoScRsp, .{}, context.arena);
}

pub fn onGetMiscDataCsReq(context: *NetContext, _: protocol.ByName(.GetMiscDataCsReq)) !protocol.ByName(.GetMiscDataScRsp) {
    return protocol.makeProto(.GetMiscDataScRsp, .{
        .retcode = 0,
        .data = try context.session.player_info.?.misc_data.toProto(context.arena),
    }, context.arena);
}

pub fn onModPostGirlCsReq(context: *NetContext, req: protocol.ByName(.ModPostGirlCsReq)) !protocol.ByName(.ModPostGirlScRsp) {
    const post_girl = &context.session.player_info.?.misc_data.post_girl;

    const random_toggle = protocol.getField(req, .post_girl_random_toggle, bool) orelse false;
    post_girl.random_toggle.set(random_toggle);

    if (protocol.getField(req, .set_show_post_girl_id_list, std.ArrayList(u32))) |set_id_list| {
        post_girl.show_post_girl.clear();

        for (set_id_list.items) |id| {
            try post_girl.show_post_girl.put(id);
        }
    }

    return protocol.makeProto(.ModPostGirlScRsp, .{}, context.arena);
}
