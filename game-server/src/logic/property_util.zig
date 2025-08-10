const std = @import("std");

pub fn isChanged(data: anytype) bool {
    const data_type = std.meta.Child(@TypeOf(data));
    inline for (std.meta.fields(data_type)) |field| {
        if (@hasDecl(@FieldType(data_type, field.name), "isChanged")) {
            if (@field(data, field.name).isChanged()) return true;
        }
    }

    return false;
}
