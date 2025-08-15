const std = @import("std");

const GameMode = @import("../logic/GameMode.zig");
const NetContext = @import("../net/NetContext.zig");
const PlayerInfo = @import("../logic/player/PlayerInfo.zig");
const protocol = @import("protocol");

const Allocator = std.mem.Allocator;
const base64 = std.base64.standard;
const log = std.log;

pub fn onPlayerGetTokenCsReq(context: *NetContext, req: protocol.ByName(.PlayerGetTokenCsReq)) !protocol.ByName(.PlayerGetTokenScRsp) {
    if (context.session.player_uid) |uid| {
        log.err("PlayerGetTokenCsReq received twice! UID: {}, source addr: {}", .{
            uid,
            context.session.connection.end_point,
        });
        return error.RepeatedGetToken;
    }

    const session = context.session;
    const allocator = session.allocator;

    session.player_uid = 1337;

    const req_client_rand_key = protocol.getField(req, .client_rand_key, protocol.protobuf.ManagedString) orelse {
        return error.ClientRandKeyNotDefined;
    };

    const client_rand_key_b64 = req_client_rand_key.getSlice();
    const client_rand_key_ciphertext = try allocator.alloc(u8, try base64.Decoder.calcSizeForSlice(client_rand_key_b64));
    defer allocator.free(client_rand_key_ciphertext);

    try base64.Decoder.decode(client_rand_key_ciphertext, client_rand_key_b64);

    var client_rand_key_bytes: [64]u8 = undefined;
    const client_rand_key_plain = session.globals.rsa.decrypt(client_rand_key_ciphertext, &client_rand_key_bytes) catch |err| {
        std.log.debug("failed to decrypt client_rand_key: {s}, reason: {}", .{ client_rand_key_b64, err });
        return error.RandKeyDecryptFail;
    };

    if (client_rand_key_plain.len != 8) return error.RandKeyInvalidSize;

    const client_rand_key = std.mem.readInt(u64, client_rand_key_plain[0..8], .little);
    const server_rand_key = std.crypto.random.int(u64);

    var server_rand_key_bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &server_rand_key_bytes, server_rand_key, .little);

    var server_rand_key_ciphertext: [128]u8 = undefined;
    var server_rand_key_signature: [64]u8 = undefined;

    session.globals.rsa.encrypt(&server_rand_key_bytes, &server_rand_key_ciphertext);
    session.globals.rsa.sign(&server_rand_key_bytes, &server_rand_key_signature);

    const server_rand_key_ciphertext_b64 = try allocator.alloc(u8, base64.Encoder.calcSize(128));
    const server_rand_key_signature_b64 = try allocator.alloc(u8, base64.Encoder.calcSize(64));

    _ = base64.Encoder.encode(server_rand_key_ciphertext_b64, &server_rand_key_ciphertext);
    _ = base64.Encoder.encode(server_rand_key_signature_b64, &server_rand_key_signature);

    try session.connection.initSessionKey(client_rand_key ^ server_rand_key);

    return protocol.makeProto(.PlayerGetTokenScRsp, .{
        .uid = session.player_uid.?,
        .server_rand_key = protocol.protobuf.ManagedString.move(server_rand_key_ciphertext_b64, allocator),
        .sign = protocol.protobuf.ManagedString.move(server_rand_key_signature_b64, allocator),
    }, allocator);
}

pub fn onPlayerLoginCsReq(context: *NetContext, _: protocol.ByName(.PlayerLoginCsReq)) !protocol.ByName(.PlayerLoginScRsp) {
    if (context.session.player_info) |info| {
        log.err("login request received twice! UID: {}, source addr: {}", .{
            info.uid,
            context.session.connection.end_point,
        });
        return error.RepeatedLogin;
    }

    const uid = context.session.player_uid orelse {
        log.err("login request received before PlayerGetToken! source addr: {}", .{
            context.session.connection.end_point,
        });
        return error.LoginBeforeGetToken;
    };

    context.session.player_info = try PlayerInfo.init(uid, context.session.allocator);
    try context.session.player_info.?.onFirstLogin(context.session.globals);
    try context.session.player_info.?.addItemsFromSettings(&context.session.globals.gameplay_settings, &context.session.globals.templates);
    context.session.player_info.?.reset();

    return protocol.makeProto(.PlayerLoginScRsp, .{}, context.arena);
}

pub fn onKeepAliveNotify(_: *NetContext, _: protocol.ByName(.KeepAliveNotify)) !void {}

pub fn onGetSelfBasicInfoCsReq(context: *NetContext, _: protocol.ByName(.GetSelfBasicInfoCsReq)) !protocol.ByName(.GetSelfBasicInfoScRsp) {
    const info = try context.session.player_info.?.ackSelfBasicInfo(context.arena);

    return protocol.makeProto(.GetSelfBasicInfoScRsp, .{
        .retcode = 0,
        .self_basic_info = info,
    }, context.arena);
}

pub fn onGetServerTimestampCsReq(context: *NetContext, _: protocol.ByName(.GetServerTimestampCsReq)) !protocol.ByName(.GetServerTimestampScRsp) {
    const timestamp: u64 = @intCast(std.time.milliTimestamp());

    return protocol.makeProto(.GetServerTimestampScRsp, .{
        .retcode = 0,
        .utc_offset = 3,
        .timestamp = timestamp,
    }, context.arena);
}

pub fn onModAvatarCsReq(context: *NetContext, req: protocol.ByName(.ModAvatarCsReq)) !protocol.ByName(.ModAvatarScRsp) {
    const player = &context.session.player_info.?;

    // TODO: implement checks (unlock for guise and 2011/2021 for avatar_id/player_avatar_id)

    if (protocol.getField(req, .avatar_id, u32)) |id| {
        player.avatar_id.set(id);
    }

    if (protocol.getField(req, .player_avatar_id, u32)) |id| {
        player.player_avatar_id.set(id);
    }

    if (protocol.getField(req, .control_guise_avatar_id, u32)) |id| {
        player.control_guise_avatar_id.set(id);
    }

    return protocol.makeProto(.ModAvatarScRsp, .{
        .retcode = 0,
    }, context.arena);
}

pub fn onGetHadalZoneDataCsReq(context: *NetContext, _: protocol.ByName(.GetHadalZoneDataCsReq)) !protocol.ByName(.GetHadalZoneDataScRsp) {
    var rsp = protocol.makeProto(.GetHadalZoneDataScRsp, .{}, context.arena);

    for (context.session.globals.gameplay_settings.hadal_entrance_list) |entrance| {
        var cur_zone_record = protocol.makeProto(.ZoneRecord, .{
            .zone_id = entrance.zone_id,
        }, context.arena);

        for (context.session.globals.templates.zone_info_template_tb.items) |zone_info_template| {
            if (zone_info_template.zone_id == @as(i32, @intCast(entrance.zone_id))) {
                const layer_record = protocol.makeProto(.LayerRecord, .{
                    .layer_index = @as(u32, @intCast(zone_info_template.layer_index)),
                    .status = 4, // Completion status
                }, context.arena);

                try protocol.addToList(&cur_zone_record, .layer_record_list, layer_record);
            }
        }

        if (entrance.getEntranceType() == .scheduled) {
            protocol.setFields(&cur_zone_record, .{
                .begin_timestamp = std.time.timestamp() - (3600 * 24),
                .end_timestamp = std.time.timestamp() + (3600 * 24 * 14),
            });
        }

        const entrance_info = protocol.makeProto(.HadalEntranceInfo, .{
            .entrance_type = @intFromEnum(entrance.getEntranceType()),
            .entrance_id = entrance.entrance_id,
            .state = 3,
            .cur_zone_record = cur_zone_record,
        }, context.arena);

        try protocol.addToList(&rsp, .hadal_entrance_list, entrance_info);
    }

    return rsp;
}

pub fn onStartHadalZoneBattleCsReq(context: *NetContext, req: protocol.ByName(.StartHadalZoneBattleCsReq)) !protocol.ByName(.StartHadalZoneBattleScRsp) {
    std.log.debug("StartHadalZoneQuest: {}", .{req});

    const retcode: i32 = blk: {
        const first_room_avatar_id_list = protocol.getField(req, .first_room_avatar_id_list, std.ArrayList(u32)) orelse break :blk 1;
        const second_room_avatar_id_list = protocol.getField(req, .second_room_avatar_id_list, std.ArrayList(u32)) orelse break :blk 1;
        const zone_id = protocol.getField(req, .zone_id, u32) orelse break :blk 1;
        const layer_index = protocol.getField(req, .layer_index, u32) orelse break :blk 1;
        const layer_item_id = protocol.getField(req, .layer_item_id, u32) orelse 0;

        const game_mode = GameMode.loadHadalZoneState(
            &context.session.player_info.?,
            &context.session.globals.templates,
            first_room_avatar_id_list.items,
            second_room_avatar_id_list.items,
            zone_id,
            layer_index,
            layer_item_id,
            context.session.allocator,
        ) catch |err| {
            std.log.debug("loadHadalZoneState failed: {}", .{err});
            break :blk 1;
        };

        if (context.session.game_mode != null) {
            context.session.game_mode.?.deinit();
        }

        context.session.game_mode = game_mode;
        break :blk 0;
    };

    return protocol.makeProto(.StartHadalZoneBattleScRsp, .{ .retcode = retcode }, context.arena);
}
