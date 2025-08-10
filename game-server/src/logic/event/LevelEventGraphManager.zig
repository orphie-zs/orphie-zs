const std = @import("std");
const protocol = @import("protocol");

const Scene = @import("../scene.zig").Scene;
const LevelEventGraph = @import("LevelEventGraph.zig");
const ConfigEvent = @import("../../data/graph/event_config.zig").ConfigEvent;

const Allocator = std.mem.Allocator;
const HashMap = std.AutoArrayHashMapUnmanaged;
const Self = @This();

gpa: Allocator,
level: Scene,
cur_interact_id: ?u32,
run_graphs: HashMap(u32, *LevelEventGraph),

pub fn init(gpa: Allocator, level: Scene) Self {
    return .{
        .gpa = gpa,
        .level = level,
        .run_graphs = .empty,
        .cur_interact_id = null,
    };
}

pub fn deinit(self: *@This()) void {
    var graphs = self.run_graphs.iterator();
    while (graphs.next()) |entry| {
        entry.value_ptr.*.deinit();
        self.gpa.destroy(entry.value_ptr.*);
    }

    self.run_graphs.deinit(self.gpa);
}

pub fn startEvent(self: *Self, section_id: u32, graph_id: u32, config: *const HashMap(u32, ConfigEvent), event_id: u32) !void {
    if (self.run_graphs.get(graph_id)) |graph| {
        graph.deinit();
        self.gpa.destroy(graph);
        _ = self.run_graphs.swapRemove(graph_id);
    }

    const uid = 0;
    const graph = try self.gpa.create(LevelEventGraph);
    graph.* = LevelEventGraph.init(uid, section_id, self.level, config, self.gpa);

    try self.run_graphs.put(self.gpa, graph_id, graph);
    try graph.run(event_id, null);
}

// TODO: API to resume event

pub fn flushNetEvents(self: *Self, context: anytype) !void {
    var graphs = self.run_graphs.iterator();
    while (graphs.next()) |entry| {
        const graph = entry.value_ptr.*;

        if (shouldNotifyEventToClient(graph)) {
            var notify = protocol.makeProto(.SectionEventScNotify, .{ .section_id = graph.section_id }, context.arena);

            for (graph.last_run_nodes.items) |node_action| {
                switch (node_action.inner) {
                    inline else => |action| {
                        const Action = @TypeOf(action);
                        if (@hasDecl(Action, "toProto")) {
                            const proto = try action.toProto(self.gpa);
                            defer proto.deinit();

                            const buffer = try proto.encode(context.arena);
                            const action_type = @intFromEnum(std.meta.activeTag(node_action.inner));

                            const action_info = protocol.makeProto(.ActionInfo, .{
                                .body = protocol.protobuf.ManagedString.move(buffer, context.arena),
                                .action_type = action_type,
                            }, context.arena);

                            try protocol.addToList(&notify, .action_list, action_info);
                        }
                    },
                }
            }

            graph.last_run_nodes.clearRetainingCapacity();
            try context.notify(notify);
        }
    }

    self.clearAllEvents();
}

fn clearAllEvents(self: *Self) void {
    var graphs = self.run_graphs.iterator();
    while (graphs.next()) |entry| {
        entry.value_ptr.*.clearHandle();
    }
}

fn shouldNotifyEventToClient(graph: *const LevelEventGraph) bool {
    var handles = graph.handles.iterator();

    while (handles.next()) |handle| {
        if (handle.value_ptr.state == .waiting_client) return true;
    }

    for (graph.last_run_nodes.items) |node| {
        if (node.isExecutableOnBothSides()) return true;
    }

    return false;
}
