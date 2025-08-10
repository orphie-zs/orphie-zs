const std = @import("std");
const network = @import("network");

const ControlPacket = @import("packet.zig").ControlPacket;
const PlayerSession = @import("PlayerSession.zig");
const Globals = @import("../Globals.zig");
const MinKcpPacketSize: usize = @as(usize, @import("kcp.zig").IKCP_OVERHEAD);

const log = std.log;
const random = std.crypto.random;
const Allocator = std.mem.Allocator;
const SessionMap = std.AutoArrayHashMapUnmanaged(u32, *PlayerSession);

threadlocal var udp_socket: ?network.Socket = null;

pub fn listen(allocator: Allocator, addr: []const u8, port: u16, shutdown_on_disconnect: bool, globals: *const Globals) !void {
    udp_socket = try network.Socket.create(.ipv4, .udp);

    udp_socket.?.bind(.{ .address = try network.Address.parse(addr), .port = port }) catch {
        log.err("Failed to bind at {s}:{}. Is another instance of the server already running?", .{ addr, port });
        return;
    };

    log.info("server is listening at udp://{s}:{}", .{ addr, port });

    var session_map = SessionMap.empty;
    var conv_counter: u32 = 0;
    var buf: [1400]u8 = undefined;

    while (true) {
        const result = try udp_socket.?.receiveFrom(&buf);

        if (result.numberOfBytes == ControlPacket.size) {
            const bytes = buf[0..ControlPacket.size];
            const control_type = ControlPacket.getType(bytes) orelse {
                log.warn("received invalid control packet type from {}", .{result.sender});
                continue;
            };

            switch (control_type) {
                ControlPacket.Type.connect => {
                    conv_counter += 1;
                    const conv = conv_counter;
                    const token = random.int(u32);

                    const session_ptr = try PlayerSession.init(allocator, conv, token, result.sender, globals);
                    session_ptr.connection.kcp.setOutput(kcpOutput);
                    try session_map.put(allocator, conv, session_ptr);

                    const buffer = ControlPacket.build(ControlPacket.Type.send_back_conv, conv, token, 0);
                    _ = udp_socket.?.sendTo(result.sender, &buffer) catch continue;

                    log.info("new connection from {}, conv: {}", .{ result.sender, conv });
                },
                ControlPacket.Type.send_back_conv => {
                    log.warn("received SendBackConv packet from {}", .{result.sender});
                },
                ControlPacket.Type.disconnect => {
                    const conv = ControlPacket.getConv(bytes);
                    const token = ControlPacket.getToken(bytes);

                    if (session_map.get(conv)) |session_ptr| {
                        if (session_ptr.connection.kcp.token != token) continue;

                        session_ptr.deinit();
                        _ = session_map.swapRemove(conv);

                        log.info("session from {} disconnected", .{result.sender});

                        if (shutdown_on_disconnect and session_map.count() == 0) {
                            session_map.deinit(allocator);
                            return;
                        }
                    }
                },
            }
        } else if (result.numberOfBytes >= MinKcpPacketSize) {
            const conv = std.mem.readInt(u32, buf[0..4], .little);
            const token = std.mem.readInt(u32, buf[4..8], .little);

            const session_ptr = session_map.get(conv) orelse {
                log.warn("session with conv {} not found, sender addr: {}", .{ conv, result.sender });

                // Send disconnect packet to trigger pop-up on client
                const buffer = ControlPacket.build(ControlPacket.Type.disconnect, conv, token, 5);
                _ = udp_socket.?.sendTo(result.sender, &buffer) catch continue;

                continue;
            };

            if (session_ptr.connection.kcp.token != token) {
                log.warn("potential amplification attempt from {}, target conv: {}", .{ result.sender, conv });
                continue;
            }

            session_ptr.onReceive(buf[0..result.numberOfBytes]) catch |err| {
                log.err("onReceive failed: {}", .{err});

                session_ptr.deinit();
                _ = session_map.swapRemove(conv);

                const buffer = ControlPacket.build(ControlPacket.Type.disconnect, conv, token, 5);
                _ = udp_socket.?.sendTo(result.sender, &buffer) catch continue;

                log.info("session from {} forcefully disconnected due to an error", .{result.sender});
            };
        }
    }
}

fn kcpOutput(buf: []const u8, conv: u32, user: ?usize) usize {
    const session: *PlayerSession = @ptrFromInt(user.?);
    return udp_socket.?.sendTo(session.connection.end_point, buf) catch |err| {
        log.debug("sendto failed, conv: {}, end_point: {}, data_len: {}, error: {}", .{
            conv,
            session.connection.end_point,
            buf.len,
            err,
        });
        return 0;
    };
}
