const builtin = @import("builtin");
const std = @import("std");

const debug = std.debug;
const io = std.io;
const math = std.math;
const mem = std.mem;
const meta = std.meta;
const time = std.time;

const Decl = builtin.TypeInfo.Declaration;

pub fn benchmark(comptime B: type) !void {
    const args = if (@hasDecl(B, "args")) B.args else [_]void{{}};
    const iterations: u32 = if (@hasDecl(B, "iterations")) B.iterations else 100000;

    comptime var max_fn_name_len = 0;
    const functions = comptime blk: {
        var res: []const Decl = &[_]Decl{};
        for (meta.declarations(B)) |decl| {
            if (decl.data != Decl.Data.Fn)
                continue;

            if (max_fn_name_len < decl.name.len)
                max_fn_name_len = decl.name.len;
            res = res ++ [_]Decl{decl};
        }

        break :blk res;
    };
    if (functions.len == 0)
        @compileError("No benchmarks to run.");

    const max_name_spaces = comptime math.max(max_fn_name_len + digits(u64, 10, args.len) + 1, "Benchmark".len);

    var timer = try time.Timer.start();
    debug.warn("\n");
    debug.warn("Benchmark");
    nTimes(' ', (max_name_spaces - "Benchmark".len) + 1);
    nTimes(' ', digits(u64, 10, math.maxInt(u64)) - "Mean(ns)".len);
    debug.warn("Mean(ns)\n");
    nTimes('-', max_name_spaces + digits(u64, 10, math.maxInt(u64)) + 1);
    debug.warn("\n");

    inline for (functions) |def| {
        for (args) |arg, index| {
            var runtime_sum: u128 = 0;

            var i: usize = 0;
            while (i < iterations) : (i += 1) {
                timer.reset();

                const res = switch (@typeOf(arg)) {
                    void => @noInlineCall(@field(B, def.name)),
                    else => @noInlineCall(@field(B, def.name), arg),
                };

                const runtime = timer.read();
                runtime_sum += runtime;
                doNotOptimize(res);
            }

            const runtime_mean = @intCast(u64, runtime_sum / iterations);

            debug.warn("{}.{}", def.name, index);
            nTimes(' ', (max_name_spaces - (def.name.len + digits(u64, 10, index) + 1)) + 1);
            nTimes(' ', digits(u64, 10, math.maxInt(u64)) - digits(u64, 10, runtime_mean));
            debug.warn("{}\n", runtime_mean);
        }
    }
}

/// Pretend to use the value so the optimizer cant optimize it out.
fn doNotOptimize(val: var) void {
    const T = @typeOf(val);
    var store: T = undefined;
    @ptrCast(*volatile T, &store).* = val;
}

fn digits(comptime N: type, comptime base: comptime_int, n: N) usize {
    comptime var res = 1;
    comptime var check = base;

    inline while (check <= math.maxInt(N)) : ({
        check *= base;
        res += 1;
    }) {
        if (n < check)
            return res;
    }

    return res;
}

fn nTimes(c: u8, times: usize) void {
    var i: usize = 0;
    while (i < times) : (i += 1)
        debug.warn("{c}", c);
}

const bitscan = @import("main.zig");
var empty align(16) = [_]u8{0} ** 1024;
test "Bitscan benchmark" {
    try benchmark(struct {
        const Arg = struct {
            len: usize,
        };

        pub const args = [_]Arg{
            Arg{ .len = 1 },
            Arg{ .len = 2 },
            Arg{ .len = 4 },
            Arg{ .len = 8 },
            Arg{ .len = 16 },
            Arg{ .len = 32 },
        };

        pub const iterations = 10000;

        pub fn Naive(a: Arg) void {
            var n = bitscan.Naive.init(empty[0..]);
            _ = n.scan(a.len);
        }

        pub fn Skip(a: Arg) void {
            var s = bitscan.Skip.init(empty[0..]);
            _ = s.scan(a.len);
        }

        pub fn Swar64(a: Arg) void {
            var s = bitscan.Swar64.init(empty[0..]);
            _ = s.scan(a.len);
        }

        pub fn Swar128(a: Arg) void {
            var s = bitscan.Swar128.init(empty[0..]);
            _ = s.scan(a.len);
        }
    });
}
