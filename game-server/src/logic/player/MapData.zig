const std = @import("std");
const protocol = @import("protocol");

const PropertyHashMap = @import("../property.zig").PropertyHashMap;
const TemplateCollection = @import("../../data/templates.zig").TemplateCollection;

const Allocator = std.mem.Allocator;
const Self = @This();

pub const AreaGroup = struct {
    group_id: u32,
    progress: u32,
};

pub const AreaStreet = struct {
    id: u32,
    progress: u32,
    is_area_pop_show: u1 = 0,
    is_urban_area_show: u1 = 0,
    is_3d_area_show: u1 = 0,
};

group: PropertyHashMap(u32, AreaGroup),
street: PropertyHashMap(u32, AreaStreet),

pub fn init(allocator: Allocator) Self {
    return .{
        .group = .init(allocator),
        .street = .init(allocator),
    };
}

pub fn unlockAll(self: *Self, tmpl: *const TemplateCollection) !void {
    for (tmpl.urban_area_map_group_template_tb.items) |template| {
        try self.group.put(@intCast(template.area_group_id), .{
            .group_id = @intCast(template.area_group_id),
            .progress = 99,
        });
    }

    for (tmpl.urban_area_map_template_tb.items) |template| {
        try self.street.put(@intCast(template.area_id), .{
            .id = @intCast(template.area_id),
            .progress = 99,
        });
    }
}

pub fn toProto(self: *Self, allocator: Allocator) !protocol.ByName(.AreaMapData) {
    var data = protocol.makeProto(.AreaMapData, .{}, allocator);

    var streets = self.street.iterator();
    while (streets.next()) |entry| {
        const street = entry.value_ptr;

        try protocol.addToList(&data, .street, protocol.makeProto(.AreaStreetInfo, .{
            .area_id = street.id,
            .area_progress = street.progress,
            .is_area_pop_show = street.is_area_pop_show != 0,
            .is_urban_area_show = street.is_urban_area_show != 0,
            .is_3d_area_show = street.is_3d_area_show != 0,
            .is_unlocked = true,
        }, allocator));
    }

    var groups = self.group.iterator();
    while (groups.next()) |entry| {
        const group = entry.value_ptr;

        try protocol.addToList(&data, .group, protocol.makeProto(.AreaGroupInfo, .{
            .group_id = group.group_id,
            .area_progress = group.progress,
            .is_unlocked = true,
        }, allocator));
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
