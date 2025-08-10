const std = @import("std");
const Base64Decoder = std.base64.standard.Decoder;

const Self = @This();
const xorpad_size = 4096;
pub const defaults = @embedFile("gameserver_config.default.zon");

udp_addr: []const u8,
udp_port: u16,
shutdown_on_disconnect: bool,
client_public_key_der: []const u8,
server_private_key_der: []const u8,
initial_xorpad: []const u8,

pub fn getXorpad(self: *const Self) ![xorpad_size]u8 {
    var xorpad: [xorpad_size]u8 = undefined;

    const size = try Base64Decoder.calcSizeForSlice(self.initial_xorpad);
    if (size != xorpad_size) return error.InvalidXorpadSize;

    try Base64Decoder.decode(&xorpad, self.initial_xorpad);
    return xorpad;
}

pub fn clientPublicKeyDer(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
    const output = try allocator.alloc(u8, try Base64Decoder.calcSizeForSlice(self.client_public_key_der));
    errdefer allocator.free(output);

    try Base64Decoder.decode(output, self.client_public_key_der);
    return output;
}

pub fn serverPrivateKeyDer(self: *const Self, allocator: std.mem.Allocator) ![]const u8 {
    const output = try allocator.alloc(u8, try Base64Decoder.calcSizeForSlice(self.server_private_key_der));
    errdefer allocator.free(output);

    try Base64Decoder.decode(output, self.server_private_key_der);
    return output;
}
