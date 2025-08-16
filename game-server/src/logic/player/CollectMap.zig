const std = @import("std");
const protocol = @import("protocol");

const PropertyHashSet = @import("../property.zig").PropertyHashSet;
const TemplateCollection = @import("../../data/templates.zig").TemplateCollection;

const Allocator = std.mem.Allocator;
const Self = @This();

workbench_app_id_list: PropertyHashSet(u32),
clue_id_list: PropertyHashSet(i32),

pub fn init(allocator: Allocator) Self {
    return .{
        .workbench_app_id_list = .init(allocator),
        .clue_id_list = .init(allocator),
    };
}

pub fn unlockAll(self: *Self, tmpl: *const TemplateCollection) !void {
    for (tmpl.work_bench_app_dex_template_tb.items) |template| {
        try self.workbench_app_id_list.put(@intCast(template.id));
    }

    for (tmpl.clue_config_template_tb.items) |template| {
        try self.clue_id_list.put(template.clue_id);
    }
}

pub fn getClueBoard(self: *Self, allocator: Allocator) !protocol.ByName(.ClueBoardInfo) {
    var info = protocol.makeProto(.ClueBoardInfo, .{}, allocator);

    for (self.clue_id_list.values()) |clue_id| {
        try protocol.addToList(&info, .clue_id_list, clue_id);
    }

    return info;
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
