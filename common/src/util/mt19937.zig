// Backported from zig 0.2.0 std. Lol.

const std = @import("std");
const math = std.math;

pub const MT19937_64 = MersenneTwister(
    u64,
    312,
    156,
    31,
    0xB5026F5AA96619E9,
    29,
    0x5555555555555555,
    17,
    0x71D67FFFEDA60000,
    37,
    0xFFF7EEE000000000,
    43,
    6364136223846793005,
);

fn MersenneTwister(
    comptime int: type,
    comptime n: usize,
    comptime m: usize,
    comptime r: int,
    comptime a: int,
    comptime u: math.Log2Int(int),
    comptime d: int,
    comptime s: math.Log2Int(int),
    comptime b: int,
    comptime t: math.Log2Int(int),
    comptime c: int,
    comptime l: math.Log2Int(int),
    comptime f: int,
) type {
    return struct {
        const Self = @This();

        array: [n]int,
        index: usize,

        pub fn init(seed: int) Self {
            var mt = Self{
                .array = undefined,
                .index = n,
            };

            var prev_value = seed;
            mt.array[0] = prev_value;
            var i: usize = 1;
            while (i < n) : (i += 1) {
                prev_value = @as(int, i) +% f *% (prev_value ^ (prev_value >> (@bitSizeOf(int) - 2)));
                mt.array[i] = prev_value;
            }
            return mt;
        }

        pub fn get(mt: *Self) int {
            const mag01: [2]int = .{ 0, a };
            const LM: int = (1 << r) - 1;
            const UM = ~LM;

            if (mt.index >= n) {
                var i: usize = 0;

                while (i < n - m) : (i += 1) {
                    const x = (mt.array[i] & UM) | (mt.array[i + 1] & LM);
                    mt.array[i] = mt.array[i + m] ^ (x >> 1) ^ mag01[@as(usize, x & 0x1)];
                }

                while (i < n - 1) : (i += 1) {
                    const x = (mt.array[i] & UM) | (mt.array[i + 1] & LM);
                    mt.array[i] = mt.array[i + m - n] ^ (x >> 1) ^ mag01[@as(usize, x & 0x1)];
                }
                const x = (mt.array[i] & UM) | (mt.array[0] & LM);
                mt.array[i] = mt.array[m - 1] ^ (x >> 1) ^ mag01[@as(usize, x & 0x1)];

                mt.index = 0;
            }

            var x = mt.array[mt.index];
            mt.index += 1;

            x ^= ((x >> u) & d);
            x ^= ((x << s) & b);
            x ^= ((x << t) & c);
            x ^= (x >> l);

            return x;
        }
    };
}
