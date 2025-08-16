const std = @import("std");

const NetContext = @import("../net/NetContext.zig");
const protocol = @import("protocol");

pub fn onGetWorkBenchDataCsReq(context: *NetContext, _: protocol.ByName(.GetWorkBenchDataCsReq)) !protocol.ByName(.GetWorkBenchDataScRsp) {
    const collect_map = &context.session.player_info.?.collect_map;
    var data = protocol.makeProto(.WorkBenchData, .{
        .clue_board_info = try collect_map.getClueBoard(context.arena),
    }, context.arena);

    for (collect_map.workbench_app_id_list.values()) |id| {
        try protocol.addToList(&data, .app_id_list, id);
    }

    return protocol.makeProto(.GetWorkBenchDataScRsp, .{
        .retcode = 0,
        .work_bench_data = data,
    }, context.arena);
}
