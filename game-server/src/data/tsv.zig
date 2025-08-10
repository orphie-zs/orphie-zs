const std = @import("std");

const tb_items_field = "items";
const map_name_suffix = "_indexes";
const tsv_true = "TRUE";
const tsv_false = "FALSE";

pub fn TemplateTb(comptime Template: type, comptime key: anytype) type {
    const key_name = @tagName(key);
    const key_type = @FieldType(Template, key_name);

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &.{
                .{
                    .name = tb_items_field,
                    .type = []const Template,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf([]const Template),
                },
                .{
                    .name = @tagName(key) ++ map_name_suffix,
                    .type = std.AutoArrayHashMapUnmanaged(key_type, usize),
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(std.AutoArrayHashMapUnmanaged(key_type, usize)),
                },
            },
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

pub inline fn keyMapName(comptime TB: type) []const u8 {
    inline for (std.meta.fields(TB)) |field| {
        if (comptime std.mem.endsWith(u8, @as([]const u8, @ptrCast(field.name)), map_name_suffix)) {
            return field.name;
        }
    }

    @compileError(@typeName(TB) ++ " doesn't have key index map field");
}

inline fn keyName(comptime TB: type) []const u8 {
    const name = keyMapName(TB);
    return name[0 .. name.len - map_name_suffix.len];
}

pub fn parseFromSlice(comptime TB: type, slice: []const u8, allocator: std.mem.Allocator) !TB {
    const item_type = std.meta.Elem(@FieldType(TB, tb_items_field));

    const header_len = std.mem.indexOfScalar(u8, slice, '\n') orelse return error.MissingNewline;
    if (!isHeaderValid(item_type, slice[0..header_len])) return error.InvalidHeader;

    const data = slice[header_len + 1 .. slice.len];
    const item_count = std.mem.count(u8, data, &.{'\n'});

    const output = try allocator.alloc(item_type, item_count);

    var rows = std.mem.tokenizeScalar(u8, data, '\n');

    for (0..item_count) |i| {
        const item = &output[i];
        var values = std.mem.tokenizeScalar(u8, rows.next().?, '\t');

        inline for (std.meta.fields(item_type)) |field| {
            const value = values.next() orelse return error.UnexpectedEndOfRow;
            @field(item, field.name) = try parseValue(field.type, value, allocator);
        }
    }

    const key_map_type = @FieldType(TB, keyName(TB) ++ map_name_suffix);
    var map = key_map_type.empty;

    for (output, 0..item_count) |item, i| {
        const key = @field(item, keyName(TB));
        try map.put(allocator, key, i);
    }

    var template_tb: TB = undefined;
    @field(template_tb, tb_items_field) = output;
    @field(template_tb, keyName(TB) ++ map_name_suffix) = map;

    return template_tb;
}

inline fn parseValue(comptime T: type, input: []const u8, allocator: std.mem.Allocator) !T {
    if (T == void) return {};
    if (T == i32) return try std.fmt.parseInt(i32, input, 10);
    if (T == f32) return try std.fmt.parseFloat(f32, input);
    if (T == bool) {
        if (std.mem.eql(u8, input, tsv_true)) return true;
        if (std.mem.eql(u8, input, tsv_false)) return false;
        return error.InvalidBooleanValue;
    }
    if (T == []const u8) {
        if (input[0] != '"' or input[input.len - 1] != '"') return error.MalformedString;
        return allocator.dupe(u8, input[1 .. input.len - 1]);
    }

    switch (@typeInfo(T)) {
        inline .pointer => |info| switch (info.size) {
            inline .slice => |_| {
                if (input[0] != '[' or input[input.len - 1] != ']') return error.MalformedArray;

                const elem = std.meta.Elem(T);
                const count = if (input.len > 2) std.mem.count(u8, input, &.{'|'}) + 1 else 0;
                const output = try allocator.alloc(elem, count);
                var values = std.mem.tokenizeScalar(u8, input[1 .. input.len - 1], '|');

                for (0..count) |i| {
                    output[i] = try parseValue(elem, values.next().?, allocator);
                }

                return output;
            },
            inline else => |case| @compileError("TSV parser does not support pointer kind: " ++ @tagName(case)),
        },
        inline else => |case| @compileError("TSV parser does not support type: " ++ @tagName(case)),
    }
}

fn isHeaderValid(comptime T: type, header: []const u8) bool {
    var names = std.mem.tokenizeScalar(u8, header, '\t');

    inline for (std.meta.fields(T)) |field| {
        const name = names.next() orelse return false;

        if (!std.mem.eql(u8, name, field.name[0..field.name.len])) {
            return false;
        }
    }

    return true;
}
