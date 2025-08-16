const std = @import("std");
const protocol = @import("protocol");

const ByName = protocol.ByName;
const makeProto = protocol.makeProto;

const PropertyHashSet = @import("../property.zig").PropertyHashSet;
const TemplateCollection = @import("../../data/templates.zig").TemplateCollection;

const Allocator = std.mem.Allocator;
const Self = @This();

tips_list: PropertyHashSet(i32),
tips_group: PropertyHashSet(i32),
loading_page_tips: PropertyHashSet(i32),
lock_tips_list: PropertyHashSet(u32),

pub fn init(allocator: Allocator) Self {
    return .{
        .tips_list = .init(allocator),
        .tips_group = .init(allocator),
        .loading_page_tips = .init(allocator),
        .lock_tips_list = .init(allocator),
    };
}

pub fn unlockAll(self: *Self, tmpl: *const TemplateCollection) !void {
    for (tmpl.tips_config_template_tb.items) |template| {
        try self.tips_list.put(template.tips_id);
    }

    for (tmpl.tips_group_config_template_tb.items) |template| {
        try self.tips_group.put(template.group_id);
    }

    for (tmpl.loading_page_tips_template_tb.items) |template| {
        try self.loading_page_tips.put(template.id);
    }

    for (tmpl.lock_tip_config_template_tb.items) |template| {
        try self.lock_tips_list.put(@intCast(template.id));
    }
}

pub fn toProto(self: *Self, allocator: Allocator) !ByName(.TipsData) {
    var tips = makeProto(.TipsInfo, .{}, allocator);
    var loading_page_tips = makeProto(.LoadingPageTipsInfo, .{}, allocator);
    var lock_tips = makeProto(.LockTipsInfo, .{}, allocator);

    for (self.tips_list.values()) |id| {
        try protocol.addToList(&tips, .tips_list, id);
    }

    for (self.tips_group.values()) |id| {
        try protocol.addToList(&tips, .tips_group_list, id);
    }

    for (self.loading_page_tips.values()) |id| {
        try protocol.addToList(&loading_page_tips, .unlocked_list, id);
    }

    for (self.lock_tips_list.values()) |id| {
        try protocol.addToList(&lock_tips, .lock_tips_id_list, id);
    }

    return makeProto(.TipsData, .{
        .tips = tips,
        .loading_page_tips = loading_page_tips,
        .lock_tips = lock_tips,
    }, allocator);
}

pub fn isChanged(self: *const Self) bool {
    inline for (std.meta.fields(Self)) |field| {
        if (@hasDecl(@FieldType(Self, field.name), "isChanged")) {
            if (@field(self, field.name).isChanged()) return true;
        }
    }

    return false;
}

pub fn ackPlayerSync(_: *const Self, _: *protocol.ByName(.PlayerSyncScNotify), _: Allocator) !void {
    // ackPlayerSync.
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
