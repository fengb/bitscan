const std = @import("std");

pub const Naive = struct {
    packed_data: std.PackedIntSlice(u1),

    pub fn init(data: []u8) Naive {
        return .{ .packed_data = std.PackedIntSlice(u1).init(data, data.len * 8) };
    }

    pub fn scan(self: Naive, contiguous: usize) ?usize {
        var found_idx: usize = 0;
        var found_size: usize = 0;

        var i: usize = 0;
        while (i < self.packed_data.int_count) : (i += 1) {
            if (self.packed_data.get(i) == 0) {
                found_size = 0;
            } else {
                if (found_size == 0) {
                    found_idx = i;
                }
                found_size += 1;

                if (found_size >= contiguous) {
                    return found_idx;
                }
            }
        }
        return null;
    }

    pub fn mark(self: *Naive, start: usize, len: usize) void {
        var i: usize = 0;
        while (i < len) : (i += 1) {
            self.packed_data.set(start + i, 1);
        }
    }
};

pub const Skip = struct {
    packed_data: std.PackedIntSlice(u1),
    block_data: []u128,

    pub fn init(data: []u8) Skip {
        return .{
            .packed_data = std.PackedIntSlice(u1).init(data, data.len * 8),
            .block_data = @bytesToSlice(u128, data),
        };
    }

    pub fn scan(self: Skip, contiguous: usize) ?usize {
        var found_idx: usize = 0;
        var found_size: usize = 0;

        for (self.block_data) |segment, i| {
            if (segment == 0) continue;

            var j: usize = i * 128;
            while (j < self.packed_data.int_count) : (j += 1) {
                if (self.packed_data.get(j) == 0) {
                    found_size = 0;
                    if (j > (i + 1) * 128) {
                        break;
                    }
                } else {
                    if (found_size == 0) {
                        found_idx = j;
                    }
                    found_size += 1;

                    if (found_size >= contiguous) {
                        return found_idx;
                    }
                }
            }
        }
        return null;
    }

    pub fn mark(self: *Skip, start: usize, len: usize) void {
        var i: usize = 0;
        while (i < len) : (i += 1) {
            self.packed_data.set(start + i, 1);
        }
    }
};

pub const Swar64 = struct {
    block_data: []u64,

    const block_bits = 64;

    pub fn init(data: []align(16) u8) Swar64 {
        return .{ .block_data = @bytesToSlice(u64, data) };
    }

    // Adapted from https://lifecs.likai.org/2010/06/finding-n-consecutive-bits-of-ones-in.html
    fn matches(num: u64, count: usize) u64 {
        const stop = std.math.floorPowerOfTwo(u64, count);
        var result = num;

        var i: usize = 1;
        while (i < stop) : (i <<= 1) {
            result &= result >> @intCast(u6, i);
        }

        if (stop < count) {
            result &= (result >> @intCast(u6, count - stop));
        }

        return result;
    }

    pub fn scan(self: Swar64, contiguous: usize) ?usize {
        // TODO: search memory spanning blocks
        if (contiguous < block_bits) {
            for (self.block_data) |data, i| {
                const match = matches(data, contiguous);
                if (match > 0) {
                    // Little Endian because it's "native" to wasm.
                    const lsb = @ctz(u64, match);
                    return i * block_bits + lsb;
                }
            }
        }
        return null;
    }

    pub fn mark(self: *Swar64, start: usize, len: usize) void {
        const i = start / block_bits;
        const lsb = start % block_bits;
        const mask = (@as(u64, 1) << @intCast(u6, len)) - 1;
        self.block_data[i] |= mask << @intCast(u6, lsb);
    }
};

pub const Swar128 = struct {
    block_data: []u128,

    const block_bits = 128;

    pub fn init(data: []align(16) u8) Swar128 {
        return .{ .block_data = @bytesToSlice(u128, data) };
    }

    // Adapted from https://lifecs.likai.org/2010/06/finding-n-consecutive-bits-of-ones-in.html
    fn matches(num: u128, count: usize) u128 {
        const stop = std.math.floorPowerOfTwo(u128, count);
        var result = num;

        var i: usize = 1;
        while (i < stop) : (i <<= 1) {
            result &= result >> @intCast(u7, i);
        }

        if (stop < count) {
            result &= (result >> @intCast(u7, count - stop));
        }

        return result;
    }

    pub fn scan(self: Swar128, contiguous: usize) ?usize {
        // TODO: search memory spanning blocks
        if (contiguous < block_bits) {
            for (self.block_data) |data, i| {
                const match = matches(data, contiguous);
                if (match > 0) {
                    // Little Endian because it's "native" to wasm.
                    const lsb = @ctz(u128, match);
                    return i * block_bits + lsb;
                }
            }
        }
        return null;
    }

    pub fn mark(self: *Swar128, start: usize, len: usize) void {
        const i = start / block_bits;
        const lsb = start % block_bits;
        const mask = (@as(u128, 1) << @intCast(u7, len)) - 1;
        self.block_data[i] |= mask << @intCast(u7, lsb);
    }
};

fn testSmoke(comptime T: type) void {
    var data align(16) = [_]u8{0} ** 0x100;

    var t = T.init(data[0..]);
    std.testing.expectEqual(t.scan(1), null);

    data[0] = 1;
    std.testing.expectEqual(t.scan(1), 0);
    std.testing.expectEqual(t.scan(2), null);

    data[0xff] = 0b11000000;
    std.testing.expectEqual(t.scan(2), 2046);

    t.mark(0xff * 8 + 4, 4);
    std.testing.expectEqual(data[0xff], 0b11110000);
    t.mark(0xff * 8, 4);
    std.testing.expectEqual(data[0xff], 0b11111111);
}

test "Naive" {
    testSmoke(Naive);
}

test "Skip" {
    testSmoke(Skip);
}

test "Swar64" {
    testSmoke(Swar64);
}

test "Swar128" {
    testSmoke(Swar128);
}
