const std = @import("std");
const protocol = @import("protocol");
const UnlockInfo = @import("misc/UnlockInfo.zig");
const TeleportUnlockInfo = @import("misc/TeleportUnlockInfo.zig");
const PostGirl = @import("misc/PostGirl.zig");
const TemplateCollection = @import("../../data/templates.zig").TemplateCollection;

const Allocator = std.mem.Allocator;
const Self = @This();

unlock: UnlockInfo,
teleport_unlock: TeleportUnlockInfo,
post_girl: PostGirl,

pub fn init(allocator: Allocator) Self {
    return .{
        .unlock = .init(allocator),
        .teleport_unlock = .init(allocator),
        .post_girl = .init(allocator),
    };
}

pub fn unlockAll(self: *Self, templates: *const TemplateCollection) !void {
    for (templates.unlock_config_template_tb.items) |config| {
        try self.unlock.unlock(config);
    }

    for (templates.teleport_config_template_tb.items) |config| {
        try self.teleport_unlock.unlock(config);
    }

    for (templates.post_girl_config_template_tb.items) |config| {
        try self.post_girl.unlocked_post_girl.put(@intCast(config.id));
    }

    try self.post_girl.show_post_girl.put(3500001);
}

pub fn toProto(self: *Self, allocator: Allocator) !protocol.ByName(.MiscData) {
    var data = protocol.makeProto(.MiscData, .{}, allocator);

    inline for (std.meta.fields(Self)) |field| {
        if (@hasDecl(@FieldType(Self, field.name), "toProto")) {
            try @field(self, field.name).toProto(&data, allocator);
        }
    }

    return data;
}

pub fn isChanged(self: *const Self) bool {
    inline for (std.meta.fields(Self)) |field| {
        if (@hasDecl(@FieldType(Self, field.name), "isChanged")) {
            if (@field(self, field.name).isChanged()) return true;
        }
    }

    return false;
}

pub fn ackPlayerSync(self: *const Self, notify: *protocol.ByName(.PlayerSyncScNotify), allocator: Allocator) !void {
    var data = protocol.makeProto(.MiscSync, .{}, allocator);

    inline for (std.meta.fields(Self)) |field| {
        const field_type = @FieldType(Self, field.name);
        if (@hasDecl(field_type, "isChanged") and @hasDecl(field_type, "ackSync")) {
            if (@field(self, field.name).isChanged()) {
                try @field(self, field.name).ackSync(&data, allocator);
            }
        }
    }

    protocol.setFields(notify, .{ .misc = data });
}

pub fn reset(self: *Self) void {
    inline for (std.meta.fields(Self)) |field| {
        if (@hasDecl(@FieldType(Self, field.name), "reset")) {
            @field(self, field.name).reset();
        }
    }
}

pub fn deinit(self: *Self) void {
    inline for (std.meta.fields(Self)) |field| {
        if (@hasDecl(@FieldType(Self, field.name), "deinit")) {
            @field(self, field.name).deinit();
        }
    }
}
