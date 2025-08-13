const std = @import("std");

const NetContext = @import("../net/NetContext.zig");
const protocol = @import("protocol");
const Avatar = @import("../logic/player/Avatar.zig");
const ItemData = @import("../logic/player/ItemData.zig");

pub fn onGetAvatarDataCsReq(context: *NetContext, _: protocol.ByName(.GetAvatarDataCsReq)) !protocol.ByName(.GetAvatarDataScRsp) {
    var rsp = protocol.makeProto(.GetAvatarDataScRsp, .{}, context.arena);

    var items = context.session.player_info.?.item_data.item_map.iterator();

    while (items.next()) |entry| {
        switch (entry.value_ptr.*) {
            .avatar => |avatar| try protocol.addToList(&rsp, .avatar_list, try avatar.toProto(context.arena)),
            else => |_| {},
        }
    }

    return rsp;
}

pub fn onAvatarFavoriteCsReq(context: *NetContext, req: protocol.ByName(.AvatarFavoriteCsReq)) !protocol.ByName(.AvatarFavoriteScRsp) {
    const avatar_id = protocol.getField(req, .avatar_id, u32) orelse 0;
    const is_favorite = protocol.getField(req, .is_favorite, bool) orelse false;

    if (context.session.player_info.?.item_data.getItemPtrAs(Avatar, avatar_id)) |avatar| {
        avatar.is_favorite = is_favorite;
    }

    return protocol.makeProto(.AvatarFavoriteScRsp, .{}, context.arena);
}

pub fn onWeaponDressCsReq(context: *NetContext, req: protocol.ByName(.WeaponDressCsReq)) !protocol.ByName(.WeaponDressScRsp) {
    const avatar_id = protocol.getField(req, .avatar_id, u32) orelse 0;
    const weapon_uid = protocol.getField(req, .weapon_uid, u32) orelse 0;

    const player = &context.session.player_info.?;

    if (player.item_data.getItemPtrAs(ItemData.Weapon, weapon_uid) == null) {
        std.log.debug("WeaponDress: weapon_uid {} doesn't exist", .{weapon_uid});
        return protocol.makeProto(.WeaponDressScRsp, .{
            .retcode = 1,
        }, context.arena);
    }

    var prev_weapon_uid: ?u32 = null;

    if (player.item_data.getItemPtrAs(Avatar, avatar_id)) |avatar| {
        if (avatar.cur_weapon_uid != 0 and avatar.cur_weapon_uid != weapon_uid) prev_weapon_uid = avatar.cur_weapon_uid;
        avatar.cur_weapon_uid = weapon_uid;
    } else {
        std.log.debug("WeaponDress: avatar_id {} is not unlocked", .{avatar_id});
        return protocol.makeProto(.WeaponDressScRsp, .{
            .retcode = 1,
        }, context.arena);
    }

    var items = player.item_data.item_map.iterator();

    while (items.next()) |entry| {
        if (entry.key_ptr.* != avatar_id) {
            switch (entry.value_ptr.*) {
                .avatar => |*avatar| {
                    avatar.cur_weapon_uid = prev_weapon_uid orelse 0;
                    try player.item_data.item_map.markAsChanged(entry.key_ptr.*);
                    break;
                },
                else => |_| {},
            }
        }
    }

    return protocol.makeProto(.WeaponDressScRsp, .{
        .retcode = 0,
    }, context.arena);
}

pub fn onWeaponUnDressCsReq(context: *NetContext, req: protocol.ByName(.WeaponUnDressCsReq)) !protocol.ByName(.WeaponUnDressScRsp) {
    const avatar_id = protocol.getField(req, .avatar_id, u32) orelse 0;
    const player = &context.session.player_info.?;

    if (player.item_data.getItemPtrAs(Avatar, avatar_id)) |avatar| {
        avatar.cur_weapon_uid = 0;
    }

    return protocol.makeProto(.WeaponUnDressScRsp, .{
        .retcode = 0,
    }, context.arena);
}

pub fn onEquipmentDressCsReq(context: *NetContext, req: protocol.ByName(.EquipmentDressCsReq)) !protocol.ByName(.EquipmentDressScRsp) {
    const player = &context.session.player_info.?;

    const retcode: i32 = blk: {
        const avatar_id = protocol.getField(req, .avatar_id, u32) orelse break :blk 1;
        const equip_uid = protocol.getField(req, .equip_uid, u32) orelse break :blk 1;
        const dress_index, _ = @subWithOverflow(protocol.getField(req, .dress_index, u32) orelse break :blk 1, 1);

        if (dress_index >= Avatar.equipment_num) break :blk 1;

        if (player.item_data.getItemPtrAs(ItemData.Equip, equip_uid) == null) {
            std.log.debug("EquipmentDress: equip_uid {} doesn't exist", .{equip_uid});
            break :blk 1;
        }

        player.dressEquipment(avatar_id, equip_uid, dress_index) catch break :blk 1;

        break :blk 0;
    };

    return protocol.makeProto(.EquipmentDressScRsp, .{
        .retcode = retcode,
    }, context.arena);
}

pub fn onEquipmentSuitDressCsReq(context: *NetContext, req: protocol.ByName(.EquipmentSuitDressCsReq)) !protocol.ByName(.EquipmentSuitDressScRsp) {
    const player = &context.session.player_info.?;

    const retcode: i32 = blk: {
        const avatar_id = protocol.getField(req, .avatar_id, u32) orelse break :blk 1;
        const param_list = protocol.getField(req, .param_list, std.ArrayList(protocol.ByName(.EquipmentDressParam))) orelse break :blk 1;

        for (param_list.items) |param| {
            const equip_uid = protocol.getField(param, .equip_uid, u32) orelse break :blk 1;
            const dress_index, _ = @subWithOverflow(protocol.getField(param, .dress_index, u32) orelse break :blk 1, 1);

            if (dress_index >= Avatar.equipment_num) break :blk 1;

            if (player.item_data.getItemPtrAs(ItemData.Equip, equip_uid) == null) {
                std.log.debug("EquipmentSuitDress: equip_uid {} doesn't exist", .{equip_uid});
                break :blk 1;
            }

            player.dressEquipment(avatar_id, equip_uid, dress_index) catch break :blk 1;
        }

        break :blk 0;
    };

    return protocol.makeProto(.EquipmentSuitDressScRsp, .{
        .retcode = retcode,
    }, context.arena);
}

pub fn onEquipmentUnDressCsReq(context: *NetContext, req: protocol.ByName(.EquipmentUnDressCsReq)) !protocol.ByName(.EquipmentUnDressScRsp) {
    const player = &context.session.player_info.?;

    const retcode: i32 = blk: {
        const avatar_id = protocol.getField(req, .avatar_id, u32) orelse break :blk 1;
        const index_list = protocol.getField(req, .undress_index_list, std.ArrayList(u32)) orelse break :blk 1;

        const avatar = player.item_data.getItemPtrAs(Avatar, avatar_id) orelse {
            std.log.debug("EquipmentUnDress: avatar_id {} is not unlocked", .{avatar_id});
            break :blk 1;
        };

        for (index_list.items) |i| {
            const index, _ = @subWithOverflow(i, 1);
            if (index >= Avatar.equipment_num) continue;
            avatar.dressed_equip[index] = null;
        }

        break :blk 0;
    };

    return protocol.makeProto(.EquipmentUnDressScRsp, .{
        .retcode = retcode,
    }, context.arena);
}

pub fn onAvatarSkinDressCsReq(context: *NetContext, req: protocol.ByName(.AvatarSkinDressCsReq)) !protocol.ByName(.AvatarSkinDressScRsp) {
    const avatar_id = protocol.getField(req, .avatar_id, u32) orelse 0;
    const avatar_skin_id = protocol.getField(req, .avatar_skin_id, u32) orelse 0;

    const player = &context.session.player_info.?;

    const template = context.session.globals.templates.getConfigByKey(.avatar_skin_base_template_tb, @as(i32, @intCast(avatar_skin_id))) orelse {
        std.log.debug("AvatarSkinDress: skin {} doesn't exist", .{avatar_skin_id});
        return protocol.makeProto(.AvatarSkinDressScRsp, .{
            .retcode = 1,
        }, context.arena);
    };

    if (template.avatar_id != avatar_id) {
        std.log.debug("AvatarSkinDress: skin {} doesn't matcha avatar_id: {}", .{ avatar_skin_id, avatar_id });
        return protocol.makeProto(.AvatarSkinDressScRsp, .{
            .retcode = 1,
        }, context.arena);
    }

    if (player.item_data.getItemCount(avatar_skin_id) == 0) {
        std.log.debug("AvatarSkinDress: skin {} is not unlocked", .{avatar_skin_id});
        return protocol.makeProto(.AvatarSkinDressScRsp, .{
            .retcode = 1,
        }, context.arena);
    }

    if (player.item_data.getItemPtrAs(Avatar, avatar_id)) |avatar| {
        avatar.avatar_skin_id = avatar_skin_id;
        return protocol.makeProto(.AvatarSkinDressScRsp, .{
            .retcode = 0,
        }, context.arena);
    } else {
        std.log.debug("AvatarSkinDress: avatar {} is not unlocked", .{avatar_id});
        return protocol.makeProto(.AvatarSkinDressScRsp, .{
            .retcode = 1,
        }, context.arena);
    }
}

pub fn onAvatarSkinUnDressCsReq(context: *NetContext, req: protocol.ByName(.AvatarSkinUnDressCsReq)) !protocol.ByName(.AvatarSkinUnDressScRsp) {
    const avatar_id = protocol.getField(req, .avatar_id, u32) orelse 0;
    const player = &context.session.player_info.?;

    if (player.item_data.getItemPtrAs(Avatar, avatar_id)) |avatar| {
        avatar.avatar_skin_id = 0;
        return protocol.makeProto(.AvatarSkinUnDressScRsp, .{
            .retcode = 0,
        }, context.arena);
    } else {
        std.log.debug("AvatarSkinUnDress: avatar {} is not unlocked", .{avatar_id});
        return protocol.makeProto(.AvatarSkinUnDressScRsp, .{
            .retcode = 1,
        }, context.arena);
    }
}

pub fn onAvatarSetAwakeCsReq(context: *NetContext, req: protocol.ByName(.AvatarSetAwakeCsReq)) !protocol.ByName(.AvatarSetAwakeScRsp) {
    const retcode: i32 = blk: {
        const avatar_id = protocol.getField(req, .avatar_id, u32) orelse break :blk 1;

        const player = &context.session.player_info.?;
        const avatar = player.item_data.getItemPtrAs(Avatar, avatar_id) orelse {
            std.log.debug("AvatarSetAwakeCsReq: avatar {} is not unlocked", .{avatar_id});
            break :blk 1;
        };

        if (avatar.awake_id != 0) {
            avatar.awake_id = 0;
        } else if (context.session.globals.templates.getAvatarTemplateConfig(avatar_id)) |config| {
            if (config.battle_template.awake_ids.len != 0) {
                avatar.awake_id = @intCast(config.battle_template.awake_ids[0]);
            }
        }

        break :blk 0;
    };

    return protocol.makeProto(.AvatarSetAwakeScRsp, .{
        .retcode = retcode,
    }, context.arena);
}
