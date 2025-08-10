const std = @import("std");
const rsa = @import("rsa/rsa.zig");
const hash = std.crypto.hash;

pub const Rsa = struct {
    const Self = @This();
    const ChunkDataSize = 117;
    const PaddingSize = 11;
    const PaddedSize = ChunkDataSize + PaddingSize;
    pub const SignSize = 64;

    client_public_key: rsa.PublicKey,
    server_private_key: rsa.KeyPair,

    pub fn init(client_public_key_der: []const u8, server_private_key_der: []const u8) !Self {
        const client_public_key = rsa.PublicKey.fromDer(client_public_key_der) catch return error.InvalidClientPublicKey;
        const server_private_key = rsa.KeyPair.fromDer(server_private_key_der) catch return error.InvalidServerPrivateKey;

        return .{
            .client_public_key = client_public_key,
            .server_private_key = server_private_key,
        };
    }

    pub fn paddedLength(_: *const Self, plaintext_len: usize) usize {
        return (std.math.divCeil(usize, plaintext_len, ChunkDataSize) catch unreachable) * PaddedSize;
    }

    pub fn encrypt(self: *const Self, plaintext: []const u8, output: []u8) void {
        const numChunks = std.math.divCeil(usize, plaintext.len, ChunkDataSize) catch unreachable;

        for (0..numChunks) |n| {
            const plainChunk = plaintext[n * ChunkDataSize .. @min((n + 1) * ChunkDataSize, plaintext.len)];
            _ = self.client_public_key.encryptPkcsv1_5(plainChunk, output[n * PaddedSize .. (n + 1) * PaddedSize]) catch unreachable;
        }
    }

    pub fn decrypt(self: *const Self, ciphertext: []const u8, output: []u8) ![]const u8 {
        return try self.server_private_key.decryptPkcsv1_5(ciphertext, output);
    }

    pub fn sign(self: *const Self, plaintext: []const u8, output: *[SignSize]u8) void {
        _ = self.server_private_key.signPkcsv1_5(hash.sha2.Sha256, plaintext, output) catch unreachable;
    }
};
