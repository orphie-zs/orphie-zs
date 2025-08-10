const std = @import("std");
const protocol = @import("protocol");

const PropertyPrimitive = @import("../property.zig").PropertyPrimitive;

const Allocator = std.mem.Allocator;
const Self = @This();

const stage_list: [4]u32 = .{ 360, 720, 1080, 0 };

day_of_week: PropertyPrimitive(u32),
day_period: PropertyPrimitive(TimePeriodType),
time_in_minutes: PropertyPrimitive(u32),
is_lock_time: PropertyPrimitive(bool),

pub fn init() Self {
    return .{
        .day_of_week = .init(5),
        .day_period = .init(.none),
        .time_in_minutes = .init(360),
        .is_lock_time = .init(false),
    };
}

pub const TimePeriodType = enum(u32) {
    none = 0,
    morning = 1,
    afternoon = 2,
    evening = 3,
    night = 4,
};

pub fn setManualTime(self: *Self, period: TimePeriodType) !void {
    if (self.is_lock_time.value) return error.TimeIsLocked;

    const minutes = self.getMinutesByStage(period);
    if (minutes == self.time_in_minutes.value) return error.TimePeriodAlreadySet;

    if (minutes < self.time_in_minutes.value) {
        self.day_of_week.set((self.day_of_week.value + 1) % 7);
    }

    self.time_in_minutes.set(minutes);
}

pub fn getMinutesByStage(self: *const Self, period_type: TimePeriodType) u32 {
    if (period_type == .none) return self.time_in_minutes.value;
    return stage_list[@intFromEnum(period_type) - 1];
}

pub fn toProto(self: *Self, allocator: Allocator) !protocol.ByName(.TimeInfo) {
    return protocol.makeProto(.TimeInfo, .{
        .day_period = @intFromEnum(self.day_period.value),
        .is_lock_time = self.is_lock_time.value,
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

pub fn deinit(_: *Self) void {}
