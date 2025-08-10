const std = @import("std");

const max_comptime_rows = 25;

pub fn TsvTable(comptime template_name: []const u8) type {
    @setEvalBranchQuota(1_000_000);

    const data: []const u8 = @embedFile(template_name);

    const header_len = std.mem.indexOfScalar(u8, data, '\n') orelse @compileError("no newline at the end of header in file " ++ template_name);
    const header = data[0..header_len];

    const payload = data[header_len + 1 .. data.len];

    var names_iter = std.mem.tokenizeScalar(u8, header, '\t');
    var names: []const [:0]const u8 = &.{};

    while (names_iter.next()) |field_name| {
        const name_terminated: [:0]const u8 = @ptrCast(field_name ++ .{0});
        names = names ++ .{name_terminated};
    }

    comptime var row_count = 0;
    var rows_iter = std.mem.tokenizeScalar(u8, payload, '\n');
    while (rows_iter.next() != null and row_count < max_comptime_rows) row_count += 1;

    const rows = parseRows(payload, row_count, names.len);

    var fields: [names.len]std.builtin.Type.StructField = undefined;
    for (names, 0..names.len) |name, i| {
        const field_type = FieldType(rows, i);
        fields[i] = .{
            .name = name,
            .type = field_type,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(field_type),
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}

fn parseRows(comptime payload: []const u8, row_count: usize, field_count: usize) [row_count][field_count][]const u8 {
    var rows: [row_count][field_count][]const u8 = undefined;

    var rows_iter = std.mem.tokenizeScalar(u8, payload, '\n');
    for (0..row_count) |i| {
        var row: [field_count][]const u8 = undefined;
        var row_iter = std.mem.tokenizeScalar(u8, rows_iter.next().?, '\t');
        for (0..field_count) |j| {
            row[j] = row_iter.next().?;
        }

        rows[i] = row;
    }

    return rows;
}

fn FieldType(rows: anytype, field_index: usize) type {
    var row = rows[0];
    const raw_value = row[field_index];

    const kind = valueKind(raw_value);

    switch (kind) {
        .String => return []const u8,
        .Float => return f32,
        .Int => return i32,
        .Bool => return bool,
        else => {},
    }

    if (kind == .Array) {
        var array_items_str: []const u8 = raw_value[1 .. raw_value.len - 1];

        comptime var i: usize = 1;
        while (array_items_str.len == 0 and i < rows.len) : (i += 1) {
            row = rows[i];
            const next_raw_value = row[field_index];

            array_items_str = next_raw_value[1 .. next_raw_value.len - 1];
        }

        if (array_items_str.len == 0) {
            // array was empty in every row, fallbacking to void
            return void;
        }

        var array_items = std.mem.tokenizeScalar(u8, array_items_str, '|');
        const item = array_items.next().?;
        const item_kind = valueKind(item);

        const item_type = switch (item_kind) {
            .Int => i32,
            .Float => f32,
            .Bool => bool,
            .String => []const u8,
            .Array => @compileError("arrays of arrays are not supported yet"),
        };

        return []const item_type;
    }
}

const ValueKind = enum {
    Int,
    Float,
    Bool,
    String,
    Array,
};

fn valueKind(raw_value: []const u8) ValueKind {
    const tsv_true = "TRUE";
    const tsv_false = "FALSE";

    if (raw_value[0] == '"' and raw_value[raw_value.len - 1] == '"') {
        return .String;
    }

    if (raw_value[0] == '[' and raw_value[raw_value.len - 1] == ']') {
        return .Array;
    }

    if (isNumeric(raw_value) or raw_value[0] == '-' and isNumeric(raw_value[1..raw_value.len])) return .Int;

    if (std.mem.indexOfScalar(u8, raw_value, '.')) |dot_index| {
        if ((isNumeric(raw_value[0..dot_index]) or (raw_value[0] == '-' and isNumeric(raw_value[1..dot_index]))) and isNumeric(raw_value[dot_index + 1 .. raw_value.len])) {
            return .Float;
        }
    }

    if (std.mem.eql(u8, raw_value, tsv_true) or std.mem.eql(u8, raw_value, tsv_false)) {
        return .Bool;
    }

    @compileError("can't infer type of value: " ++ raw_value);
}

fn isNumeric(value: []const u8) bool {
    for (value) |char| {
        switch (char) {
            '0'...'9' => continue,
            else => return false,
        }
    }

    return true;
}
