const std = @import("std");
const Allocator = std.mem.Allocator;

const EventGraphTemplateMap = @import("EventGraphTemplateMap.zig");

const main_city_config_path = "assets/LevelProcess/MainCity/MainCity_1.json";
const npc_graph_dir = "assets/LevelProcess/MainCity/Interact/";

const json_attribute_default_section_id = "default_section_id";
const json_attribute_section_list = "sections";
const json_attribute_section_progress = "section_progress";

pub fn loadTemplateMap(gpa: Allocator) !EventGraphTemplateMap {
    var event_graph_map = EventGraphTemplateMap.init(gpa);
    errdefer event_graph_map.deinit();

    try loadMainCityGraph(&event_graph_map, gpa);
    try loadAllNpcGraphs(&event_graph_map, gpa);

    return event_graph_map;
}

fn loadMainCityGraph(map: *EventGraphTemplateMap, gpa: Allocator) !void {
    const content = try std.fs.cwd().readFileAllocOptions(gpa, main_city_config_path, 1024 * 1024, null, @alignOf(u8), 0);
    defer gpa.free(content);

    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, content, .{});
    defer parsed.deinit();

    map.default_main_city_section = @intCast((parsed.value.object.get(json_attribute_default_section_id) orelse return error.MissingDefaultSectionId).integer);

    var sections = parsed.value.object.get(json_attribute_section_list).?.object.iterator();
    while (sections.next()) |entry| {
        const section_id = try std.fmt.parseInt(u32, entry.key_ptr.*, 10);
        const section_progress = entry.value_ptr.*.object.get(json_attribute_section_progress) orelse return error.MissingSectionProgress;

        try map.parseSectionEventGraphConfig(section_id, section_progress, gpa);
    }
}

fn loadAllNpcGraphs(map: *EventGraphTemplateMap, gpa: Allocator) !void {
    var graph_dir = std.fs.cwd().openDir(npc_graph_dir, .{ .iterate = true }) catch return error.FailedToOpenNpcGraphDir;
    defer graph_dir.close();

    var walker = try graph_dir.walk(gpa);
    defer walker.deinit();

    while (true) {
        const entry = walker.next() catch break orelse break;
        if (entry.kind == .file) {
            const content = try graph_dir.readFileAllocOptions(gpa, entry.path, 1024 * 1024, null, @alignOf(u8), 0);
            defer gpa.free(content);

            const parsed = try std.json.parseFromSlice(std.json.Value, gpa, content, .{});
            defer parsed.deinit();

            try map.parseNpcEventGraphConfig(parsed.value, gpa);
        }
    }
}
