const std = @import("std");

pub const ControlPacket = packed struct {
    pub const size: usize = 20;

    pub const Type = enum(u64) {
        connect = 0xFFFFFFFFFF,
        send_back_conv = 0x14514514545,
        disconnect = 0x19419419494,
    };

    pub fn build(control_type: Type, conv: u32, token: u32, data: u32) [20]u8 {
        var buffer: [size]u8 = undefined;

        const type_long = @intFromEnum(control_type);
        std.mem.writeInt(u32, buffer[0..4], @intCast(type_long >> 32), .big);
        std.mem.writeInt(u32, buffer[4..8], conv, .big);
        std.mem.writeInt(u32, buffer[8..12], token, .big);
        std.mem.writeInt(u32, buffer[12..16], data, .big);
        std.mem.writeInt(u32, buffer[16..20], @intCast(type_long & 0xFFFFFFFF), .big);

        return buffer;
    }

    pub fn getType(buf: *const [size]u8) ?Type {
        const head_magic = std.mem.readInt(u32, buf[0..4], .big);
        const tail_magic = std.mem.readInt(u32, buf[16..20], .big);
        return getTypeFromMagic(head_magic, tail_magic);
    }

    pub fn getConv(buf: *const [size]u8) u32 {
        return std.mem.readInt(u32, buf[4..8], .big);
    }

    pub fn getToken(buf: *const [size]u8) u32 {
        return std.mem.readInt(u32, buf[8..12], .big);
    }

    pub fn getData(buf: *const [size]u8) u32 {
        return std.mem.readInt(u32, buf[12..16], .big);
    }

    fn getTypeFromMagic(head: u32, tail: u32) ?Type {
        const long = (@as(u64, head) << 32) | @as(u64, tail);
        return std.meta.intToEnum(Type, long) catch return null;
    }
};

pub const NetPacket = struct {
    const head_magic: [4]u8 = .{ 0x01, 0x23, 0x45, 0x67 };
    const tail_magic: [4]u8 = .{ 0x89, 0xAB, 0xCD, 0xEF };
    pub const minimal_length: usize = 16;

    pub const DecodeError = error{
        PacketNotCorrect,
        PacketNotComplete,
    };

    head: []const u8,
    body: []u8,
    cmd_id: u16,

    pub fn decode(buffer: []u8, output: *NetPacket) DecodeError!usize {
        if (buffer.len < minimal_length) return DecodeError.PacketNotComplete;
        if (!std.mem.eql(u8, &head_magic, buffer[0..4])) return DecodeError.PacketNotCorrect;

        const head_len: usize = @intCast(std.mem.readInt(u16, buffer[6..8], .big));
        const body_len: usize = @intCast(std.mem.readInt(u32, buffer[8..12], .big));

        const full_length = minimal_length + head_len + body_len;
        if (buffer.len < full_length) return DecodeError.PacketNotComplete;

        const tail_offset = 12 + head_len + body_len;
        if (!std.mem.eql(u8, &tail_magic, buffer[tail_offset .. tail_offset + 4])) return DecodeError.PacketNotCorrect;

        output.* = .{
            .head = buffer[12 .. head_len + 12],
            .body = buffer[12 + head_len .. 12 + head_len + body_len],
            .cmd_id = std.mem.readInt(u16, buffer[4..6], .big),
        };

        return full_length;
    }

    pub fn encode(output: []u8, cmd_id: u16, head: []const u8, body: []const u8) void {
        @memcpy(output[0..4], &head_magic);
        std.mem.writeInt(u16, output[4..6], cmd_id, .big);
        std.mem.writeInt(u16, output[6..8], @intCast(head.len), .big);
        std.mem.writeInt(u32, output[8..12], @intCast(body.len), .big);
        @memcpy(output[12 .. 12 + head.len], head);
        @memcpy(output[12 + head.len .. 12 + head.len + body.len], body);
        @memcpy(output[12 + head.len + body.len .. 16 + head.len + body.len], &tail_magic);
    }
};
