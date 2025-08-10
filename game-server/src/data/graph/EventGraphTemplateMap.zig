const std = @import("std");
const event_config = @import("event_config.zig");

const HashMap = std.AutoArrayHashMapUnmanaged;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const SectionEventGraphConfig = event_config.SectionEventGraphConfig;
const NpcEventGraphConfig = event_config.NpcEventGraphConfig;
const ConfigEvent = event_config.ConfigEvent;

const json_attribute_id = "id";
const json_attribute_events = "events";

arena: ArenaAllocator,
default_main_city_section: u32,
section_event_graphs: HashMap(u32, *SectionEventGraphConfig),
npc_event_graphs: HashMap(u32, *NpcEventGraphConfig),

pub fn init(gpa: Allocator) @This() {
    return .{
        .arena = ArenaAllocator.init(gpa),
        .default_main_city_section = 0,
        .section_event_graphs = .empty,
        .npc_event_graphs = .empty,
    };
}

pub fn deinit(self: *@This()) void {
    self.arena.deinit();
}

pub fn parseNpcEventGraphConfig(self: *@This(), content: std.json.Value, gpa: Allocator) !void {
    const arena = self.arena.allocator();
    const json_object = content.object;

    var config = try arena.create(NpcEventGraphConfig);
    config.id = @intCast((json_object.get(json_attribute_id) orelse return error.MissingID).integer);

    const events = (json_object.get(json_attribute_events) orelse return error.MissingEventList).object;
    config.events = .empty;
    config.on_interact_event_id = null;
    try config.events.ensureTotalCapacity(arena, events.count());

    var name_map_kvs = try gpa.alloc(struct { []const u8, u32 }, events.count());
    defer gpa.free(name_map_kvs);

    var events_iter = events.iterator();
    var i: usize = 0;

    while (events_iter.next()) |entry| : (i += 1) {
        const name = entry.key_ptr.*;
        const event = try ConfigEvent.parseFromJsonObject(entry.value_ptr.*.object, name, arena);

        name_map_kvs[i] = .{ try arena.dupe(u8, name), event.id };
        try config.events.put(arena, event.id, event);

        if (std.mem.eql(u8, name, NpcEventGraphConfig.on_interact_event_name)) {
            config.on_interact_event_id = event.id;
        }
    }

    config.event_name_map = try .init(name_map_kvs, arena);
    try self.npc_event_graphs.put(arena, config.id, config);
}

pub fn parseSectionEventGraphConfig(self: *@This(), section_id: u32, content: std.json.Value, gpa: Allocator) !void {
    const arena = self.arena.allocator();

    var config = try arena.create(SectionEventGraphConfig);
    config.id = section_id;

    const json_object = content.object;

    const events = (json_object.get(json_attribute_events) orelse return error.MissingEventList).object;
    config.events = .empty;
    try config.events.ensureTotalCapacity(arena, events.count());

    // temporary lookup table
    var event_name_to_id: std.StringHashMapUnmanaged(u32) = .empty;
    defer event_name_to_id.deinit(gpa);

    var events_iter = events.iterator();
    while (events_iter.next()) |entry| {
        const name = entry.key_ptr.*;
        const event = try ConfigEvent.parseFromJsonObject(entry.value_ptr.*.object, name, arena);

        try event_name_to_id.put(gpa, name, event.id);
        try config.events.put(arena, event.id, event);
    }

    inline for (SectionEventGraphConfig.event_reference_lists) |list_name| {
        if (json_object.get(list_name)) |list| {
            const items = list.array.items;
            const ids = try arena.alloc(u32, items.len);

            for (items, 0..items.len) |item, i| {
                ids[i] = event_name_to_id.get(item.string) orelse {
                    std.log.err("attempted to reference a non-existent event '{s}'", .{item.string});
                    return error.InvalidEventReference;
                };
            }

            @field(config, list_name) = ids;
        } else {
            @field(config, list_name) = &.{};
        }
    }

    try self.section_event_graphs.put(arena, section_id, config);
}
