const protocol = @import("protocol");
const Allocator = @import("std").mem.Allocator;

position: [3]f64,
rotation: [3]f64,

pub fn toProto(self: *const @This(), allocator: Allocator) !protocol.ByName(.Transform) {
    var proto = protocol.makeProto(.Transform, .{}, allocator);

    try protocol.addManyToList(&proto, .position, self.position);
    try protocol.addManyToList(&proto, .rotation, self.rotation);

    return proto;
}
