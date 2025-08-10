const std = @import("std");
const Allocator = std.mem.Allocator;

const Scene = @import("../scene.zig").Scene;
const ConfigEvent = @import("../../data/graph/event_config.zig").ConfigEvent;
const ConfigEventAction = @import("../../data/graph/ConfigEventAction.zig");
const HashMap = std.AutoArrayHashMapUnmanaged;
const ArrayList = std.ArrayListUnmanaged;

const Self = @This();

uid: u64,
section_id: u32,
gpa: Allocator,
config: *const HashMap(u32, ConfigEvent),
handles: HashMap(u32, EventRunContext),
last_run_nodes: ArrayList(*const ConfigEventAction),
level: Scene,

pub fn init(uid: u64, section_id: u32, level: Scene, config: *const HashMap(u32, ConfigEvent), gpa: Allocator) Self {
    return .{
        .uid = uid,
        .section_id = section_id,
        .gpa = gpa,
        .config = config,
        .handles = .empty,
        .last_run_nodes = .empty,
        .level = level,
    };
}

pub fn deinit(self: *Self) void {
    var handles = self.handles.iterator();
    while (handles.next()) |entry| {
        entry.value_ptr.deinit();
    }

    self.handles.deinit(self.gpa);
    self.last_run_nodes.deinit(self.gpa);
}

pub fn run(self: *Self, evt_id: u32, start_action: ?u32) !void {
    const config = self.config.getPtr(evt_id) orelse return error.InvalidEventID;
    self.last_run_nodes.clearRetainingCapacity();

    const context = blk: {
        if (self.handles.getPtr(evt_id)) |context| {
            const action_id = start_action orelse {
                std.log.warn("LevelEventGraph.run: event {} is already running!", .{evt_id});
                return error.EventAlreadyRunning;
            };

            if (context.cur_node != action_id) {
                std.log.err("LevelEventGraph.run: failed to resume event {}, cur_node: {?}, start_action: {}", .{ evt_id, context.cur_node, action_id });
                return error.InvalidStartAction;
            }

            context.onEventResumed();
            break :blk context;
        } else {
            const context = EventRunContext.init(self, evt_id, self.gpa);
            try self.handles.put(self.gpa, evt_id, context);

            break :blk self.handles.getPtr(evt_id).?;
        }
    };

    while (context.state == .running) {
        try self.runSingle(context);

        if (context.cur_node) |node| {
            try context.addNodeToPath(node);
        }
    }

    for (context.move_path.items) |action_id| {
        try self.last_run_nodes.append(self.gpa, config.getActionById(action_id) orelse continue);
    }

    if (context.state == .finish) {
        context.deinit();
        _ = self.handles.swapRemove(evt_id);
    }
}

fn runSingle(self: *Self, context: *EventRunContext) !void {
    const actions = self.config.get(context.evt_id).?.actions;
    const cur_index = blk: {
        if (context.cur_node == null) {
            if (actions.len == 0) {
                context.state = .finish;
                return;
            }

            break :blk 0;
        } else {
            break :blk for (actions, 0..actions.len) |action, i| {
                if (action) |config| if (config.getId() == context.cur_node.?) break i + 1;
            } else return error.CurNodeIsInvalid;
        }
    };

    const next_action: *const ConfigEventAction = for (actions[cur_index..actions.len]) |action| {
        if (action) |*config| break config;
    } else {
        context.cur_node = null;
        context.state = .finish;
        return;
    };

    context.cur_node = next_action.getId();
    try next_action.run(context);
}

pub fn clearHandle(self: *Self) void {
    var handles = self.handles.iterator();

    while (handles.next()) |entry| {
        if (entry.value_ptr.state == .finish) {
            _ = self.handles.swapRemove(entry.key_ptr.*);
        }
    }
}

pub const EventRunContext = struct {
    evt_id: u32,
    cur_node: ?u32,
    graph: *Self,
    state: LevelNodeState,
    gpa: Allocator,
    move_path: ArrayList(u32),

    pub fn init(graph: *Self, evt_id: u32, gpa: Allocator) @This() {
        return .{
            .graph = graph,
            .evt_id = evt_id,
            .cur_node = null,
            .state = .running,
            .gpa = gpa,
            .move_path = .empty,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.move_path.deinit(self.gpa);
    }

    pub fn onEventResumed(self: *@This()) void {
        self.state = .running;
        self.move_path.clearAndFree(self.gpa);
    }

    pub fn addNodeToPath(self: *@This(), node_id: u32) !void {
        try self.move_path.append(self.gpa, node_id);
    }

    pub fn interrupt(self: *@This()) void {
        self.state = .waiting_client;
    }
};

pub const LevelNodeState = enum {
    finish,
    running,
    waiting_client,
};
