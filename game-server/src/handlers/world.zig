const std = @import("std");

const NetContext = @import("../net/NetContext.zig");
const protocol = @import("protocol");
const GameMode = @import("../logic/GameMode.zig");

pub fn onEnterWorldCsReq(context: *NetContext, _: protocol.ByName(.EnterWorldCsReq)) !protocol.ByName(.EnterWorldScRsp) {
    if (context.session.game_mode != null) {
        std.log.err("EnterWorldCsReq received when GameMode is not null! player_uid: {}", .{context.session.player_uid.?});
        return protocol.makeProto(.EnterWorldScRsp, .{ .retcode = 1 }, context.arena);
    }

    context.session.game_mode = try GameMode.loadHallState(
        &context.session.player_info.?,
        context.session.globals,
        context.session.allocator,
    );

    return protocol.makeProto(.EnterWorldScRsp, .{ .retcode = 0 }, context.arena);
}

pub fn onEnterSectionCompleteCsReq(context: *NetContext, _: protocol.ByName(.EnterSectionCompleteCsReq)) !protocol.ByName(.EnterSectionCompleteScRsp) {
    return protocol.makeProto(.EnterSectionCompleteScRsp, .{ .retcode = 0 }, context.arena);
}

pub fn onInteractWithUnitCsReq(context: *NetContext, req: protocol.ByName(.InteractWithUnitCsReq)) !protocol.ByName(.InteractWithUnitScRsp) {
    std.log.debug("InteractWithUnit: {}", .{req});

    const npc_tag_id = protocol.getField(req, .npc_tag_id, i32);
    const interact_id = protocol.getField(req, .interact_id, i32);

    if (npc_tag_id == null or interact_id == null) return protocol.makeProto(.InteractWithUnitScRsp, .{ .retcode = 0 }, context.arena);

    if (context.session.game_mode == null) {
        std.log.debug("InteractWithUnitCsReq received when GameMode is null!", .{});
        return protocol.makeProto(.InteractWithUnitScRsp, .{ .retcode = 1 }, context.arena);
    }

    const hall = switch (context.session.game_mode.?.scene) {
        .hall => |scene| scene,
        else => {
            std.log.debug("InteractWithUnitCsReq received in wrong state!", .{});
            return protocol.makeProto(.InteractWithUnitScRsp, .{ .retcode = 1 }, context.arena);
        },
    };

    var retcode: i32 = 0;

    hall.interactWithUnit(@intCast(npc_tag_id.?), @intCast(interact_id.?)) catch |err| {
        if (err != error.InvalidInteraction) return err;
        retcode = 1;
    };

    return protocol.makeProto(.InteractWithUnitScRsp, .{ .retcode = retcode }, context.arena);
}

pub fn onEnterSectionCsReq(context: *NetContext, req: protocol.ByName(.EnterSectionCsReq)) !protocol.ByName(.EnterSectionScRsp) {
    const transform_id = protocol.getField(req, .transform_id, protocol.protobuf.ManagedString);
    const section_id = protocol.getField(req, .section_id, u32);

    const retcode: i32 = blk: {
        if (transform_id == null or section_id == null) {
            break :blk 1;
        }

        if (context.session.game_mode == null) {
            std.log.debug("EnterSectionCsReq received when GameMode is null!", .{});
            break :blk 1;
        }

        const hall = switch (context.session.game_mode.?.scene) {
            .hall => |scene| scene,
            else => {
                std.log.debug("EnterSectionCsReq received in wrong state!", .{});
                break :blk 1;
            },
        };

        hall.enterSection(section_id.?, transform_id.?.getSlice()) catch |err| {
            if (err == error.SameSectionID) break :blk 1;
            return err;
        };

        const player_pos = &context.session.player_info.?.pos_in_main_city;
        try player_pos.switchSection(section_id.?, transform_id.?.getSlice());

        break :blk 0;
    };

    return protocol.makeProto(.EnterSectionScRsp, .{ .retcode = retcode }, context.arena);
}

pub fn onSavePosInMainCityCsReq(context: *NetContext, req: protocol.ByName(.SavePosInMainCityCsReq)) !protocol.ByName(.SavePosInMainCityScRsp) {
    std.log.debug("SavePosInMainCity: {}", .{req});

    blk: {
        const player_pos = &context.session.player_info.?.pos_in_main_city;

        const real_save = protocol.getField(req, .real_save, bool) orelse break :blk;
        const section_id = protocol.getField(req, .section_id, u32) orelse break :blk;

        if (real_save and section_id == player_pos.section_id) {
            const pos = protocol.getField(req, .position, ?protocol.ByName(.Transform)) orelse break :blk;

            if (pos) |transform| {
                const position = protocol.getField(transform, .position, std.ArrayList(f64)) orelse break :blk;
                const rotation = protocol.getField(transform, .rotation, std.ArrayList(f64)) orelse break :blk;

                if (position.items.len == 3 and rotation.items.len == 3) {
                    player_pos.savePosition(position.items, rotation.items);
                } else {
                    std.log.debug("SavePosInMainCity: invalid vectors received, position: {any}, rotation: {any}", .{
                        position.items,
                        rotation.items,
                    });
                }
            }
        }

        if (protocol.getField(req, .lift, ?protocol.ByName(.LiftInfo)) orelse break :blk) |lift_info| {
            const lift_name = protocol.getField(lift_info, .lift_name, protocol.protobuf.ManagedString) orelse break :blk;
            const lift_status = protocol.getField(lift_info, .lift_status, u32) orelse break :blk;

            try player_pos.setLiftStatus(lift_name.getSlice(), lift_status);
        }
    }

    return protocol.makeProto(.SavePosInMainCityScRsp, .{
        .retcode = 0,
    }, context.arena);
}

pub fn onEndBattleCsReq(context: *NetContext, _: protocol.ByName(.EndBattleCsReq)) !protocol.ByName(.EndBattleScRsp) {
    return protocol.makeProto(.EndBattleScRsp, .{
        .retcode = 0,
        .fight_settle = protocol.makeProto(.FightSettle, .{}, context.arena),
    }, context.arena);
}

pub fn onLeaveCurSceneCsReq(context: *NetContext, _: protocol.ByName(.LeaveCurSceneCsReq)) !protocol.ByName(.LeaveCurSceneScRsp) {
    if (context.session.game_mode != null) {
        context.session.game_mode.?.deinit();
    }

    context.session.game_mode = try GameMode.loadHallState(
        &context.session.player_info.?,
        context.session.globals,
        context.session.allocator,
    );

    return protocol.makeProto(.LeaveCurSceneScRsp, .{ .retcode = 0 }, context.arena);
}
