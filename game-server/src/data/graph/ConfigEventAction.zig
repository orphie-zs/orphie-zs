const std = @import("std");
const action = @import("action.zig");
const EventRunContext = @import("../../logic/event/LevelEventGraph.zig").EventRunContext;

const Allocator = std.mem.Allocator;

pub const ActionType = ActionEnum(action);
const InnerUnion = ActionUnion(action);

pub const json_attribute_type = "$type";
const type_map: std.StaticStringMap(ActionType) = buildActionTypeMap();

pub fn ActionEnum(comptime Module: type) type {
    comptime var fields: []const std.builtin.Type.EnumField = &.{};

    inline for (std.meta.declarations(Module)) |decl| {
        const SubType = @field(Module, decl.name);
        if (@hasDecl(SubType, "action_type")) {
            const action_type = @field(SubType, "action_type");
            fields = fields ++ .{std.builtin.Type.EnumField{ .name = @typeName(SubType), .value = action_type }};
        }
    }

    return @Type(.{ .@"enum" = .{
        .decls = &.{},
        .tag_type = i32,
        .fields = fields,
        .is_exhaustive = true,
    } });
}

pub fn ActionUnion(comptime Module: type) type {
    comptime var fields: []const std.builtin.Type.UnionField = &.{};

    inline for (std.meta.declarations(Module)) |decl| {
        const SubType = @field(Module, decl.name);
        if (@hasDecl(SubType, "action_type")) {
            fields = fields ++ .{std.builtin.Type.UnionField{
                .name = @typeName(SubType),
                .type = SubType,
                .alignment = @alignOf(SubType),
            }};
        }
    }

    return @Type(.{ .@"union" = .{
        .layout = .auto,
        .tag_type = ActionType,
        .fields = fields,
        .decls = &.{},
    } });
}

inner: InnerUnion,

pub fn getId(self: @This()) u32 {
    return switch (self.inner) {
        inline else => |config| config.id,
    };
}

pub fn run(self: @This(), context: *EventRunContext) !void {
    switch (self.inner) {
        inline else => |*config| try config.run(context),
    }
}

pub fn isExecutableOnBothSides(self: @This()) bool {
    switch (self.inner) {
        inline else => |config| return @hasDecl(@TypeOf(config), "toProto"),
    }
}

pub fn fromJson(json: std.json.Value, arena: Allocator) !@This() {
    const type_tag = json.object.get(json_attribute_type) orelse return error.MissingTypeTag;
    const action_type = type_map.get(type_tag.string) orelse return error.UnknownActionType;

    switch (action_type) {
        inline else => |ty| {
            const tag_name = @tagName(ty);
            const Action = @FieldType(InnerUnion, tag_name);

            const parsed = try std.json.parseFromValueLeaky(Action, arena, json, .{ .ignore_unknown_fields = true });
            return .{ .inner = @unionInit(InnerUnion, tag_name, parsed) };
        },
    }
}

fn buildActionTypeMap() std.StaticStringMap(ActionType) {
    const tag_fields = @typeInfo(ActionType).@"enum".fields;
    const fields = std.meta.fields(InnerUnion);

    var kvs: [fields.len]struct { []const u8, ActionType } = undefined;

    inline for (fields, 0..fields.len) |field, i| {
        const tag_value = for (tag_fields) |tag_field| {
            if (std.mem.eql(u8, tag_field.name, field.name)) {
                break tag_field.value;
            }
        } else @compileError("no matching enum field for union field '" ++ field.name ++ "'");

        const type_tag = @field(field.type, "tag");
        kvs[i] = .{ type_tag, @enumFromInt(tag_value) };
    }

    return .initComptime(kvs);
}
