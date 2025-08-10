const std = @import("std");

const NetContext = @import("../net/NetContext.zig");
const GameMode = @import("../logic/GameMode.zig");
const protocol = @import("protocol");

const Avatar = @import("../logic/player/Avatar.zig");
const AvatarUnit = @import("../logic/battle/AvatarUnit.zig");
const ItemData = @import("../logic/player/ItemData.zig");

pub fn onGetQuestDataCsReq(context: *NetContext, req: protocol.ByName(.GetQuestDataCsReq)) !protocol.ByName(.GetQuestDataScRsp) {
    const quest_type = protocol.getField(req, .quest_type, u32) orelse 0;

    std.log.debug("GetQuestDataCsReq quest_type: {}", .{quest_type});

    return protocol.makeProto(.GetQuestDataScRsp, .{
        .retcode = 0,
        .quest_type = quest_type,
        .quest_data = protocol.makeProto(.QuestData, .{}, context.arena),
    }, context.arena);
}

pub fn onGetArchiveDataCsReq(context: *NetContext, _: protocol.ByName(.GetArchiveDataCsReq)) !protocol.ByName(.GetArchiveDataScRsp) {
    return protocol.makeProto(.GetArchiveDataScRsp, .{
        .retcode = 0,
        .archive_data = protocol.makeProto(.ArchiveData, .{}, context.arena),
    }, context.arena);
}

pub fn onGetHollowDataCsReq(context: *NetContext, _: protocol.ByName(.GetHollowDataCsReq)) !protocol.ByName(.GetHollowDataScRsp) {
    return protocol.makeProto(.GetHollowDataScRsp, .{
        .retcode = 0,
        .hollow_data = protocol.makeProto(.HollowData, .{}, context.arena),
    }, context.arena);
}

pub fn onAbyssGetDataCsReq(context: *NetContext, _: protocol.ByName(.AbyssGetDataCsReq)) !protocol.ByName(.AbyssGetDataScRsp) {
    return protocol.makeProto(.AbyssGetDataScRsp, .{ .retcode = 0 }, context.arena);
}

pub fn onAbyssArpeggioGetDataCsReq(context: *NetContext, _: protocol.ByName(.AbyssArpeggioGetDataCsReq)) !protocol.ByName(.AbyssArpeggioGetDataScRsp) {
    return protocol.makeProto(.AbyssArpeggioGetDataScRsp, .{ .retcode = 0 }, context.arena);
}

pub fn onStartTrainingQuestCsReq(context: *NetContext, req: protocol.ByName(.StartTrainingQuestCsReq)) !protocol.ByName(.StartTrainingQuestScRsp) {
    std.log.debug("StartTrainingQuest: {}", .{req});

    if (context.session.game_mode != null) {
        context.session.game_mode.?.deinit();
    }

    const avatar_id_list = protocol.getField(req, .avatar_id_list, std.ArrayList(u32)) orelse return error.AvatarIdListNotDefined;

    context.session.game_mode = try GameMode.loadFightState(
        &context.session.player_info.?,
        &context.session.globals.templates,
        avatar_id_list.items,
        context.session.allocator,
    );

    return protocol.makeProto(.StartTrainingQuestScRsp, .{ .retcode = 0 }, context.arena);
}
