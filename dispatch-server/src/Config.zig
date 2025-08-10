const std = @import("std");
const Base64Decoder = std.base64.standard.Decoder;

const Self = @This();
pub const defaults = @embedFile("dispatch_config.default.zon");

http_addr: []const u8,
http_port: u16,
bound_sid: u32,
server_list: []const ServerListConfig,

res: ResourceConfig,
client_secret_key: []const u8,
client_public_key_der: []const u8,
server_private_key_der: []const u8,

pub const ServerListConfig = struct {
    sid: u32,
    bound_version: []const u8,
    name: []const u8,
    title: []const u8,
    dispatch_url: []const u8,
    ping_url: []const u8,
    gateway_ip: []const u8,
    gateway_port: u16,
};

pub const ResourceConfig = struct {
    branch: []const u8,
    res_revision: []const u8,
    audio_revision: []const u8,
    res_base_url: []const u8,
    res_md5_files: []const u8,
    data_revision: []const u8,
    data_base_url: []const u8,
    data_md5_files: []const u8,
    silence_revision: []const u8,
    silence_base_url: []const u8,
    silence_md5_files: []const u8,
    cdn_check_url: []const u8,
};

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
