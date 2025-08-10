const std = @import("std");

const NetContext = @import("../net/NetContext.zig");
const TimeInfo = @import("../logic/player/TimeInfo.zig");
const protocol = @import("protocol");

pub fn onGetTimeInfoCsReq(context: *NetContext, _: protocol.ByName(.GetTimeInfoCsReq)) !protocol.ByName(.GetTimeInfoScRsp) {
    return protocol.makeProto(.GetTimeInfoScRsp, .{
        .retcode = 0,
        .time_info = try context.session.player_info.?.time_info.toProto(context.arena),
    }, context.arena);
}

pub fn onModMainCityTimeCsReq(context: *NetContext, req: protocol.ByName(.ModMainCityTimeCsReq)) !protocol.ByName(.ModMainCityTimeScRsp) {
    const retcode: i32 = blk: {
        const time_period = protocol.getField(req, .time_period, u32) orelse break :blk 1;
        const period_type = std.meta.intToEnum(TimeInfo.TimePeriodType, time_period) catch {
            std.log.debug("ModMainCityTimeCsReq: invalid time_period ({})", .{time_period});
            break :blk 1;
        };

        context.session.player_info.?.time_info.setManualTime(period_type) catch |err| {
            if (err == error.TimeIsLocked or err == error.TimePeriodAlreadySet) break :blk 1;
            return err;
        };

        if (context.session.game_mode) |game_mode| {
            switch (game_mode.scene) {
                .hall => |hall| try hall.onTimeOfDayChanged(),
                else => {},
            }
        }

        break :blk 0;
    };

    return protocol.makeProto(.ModMainCityTimeScRsp, .{
        .retcode = retcode,
    }, context.arena);
}
