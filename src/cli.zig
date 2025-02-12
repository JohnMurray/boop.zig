const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// Reads the first (non-program) argument and returns it as a ArrayList of u8.
/// Caller must free the memory when done with the ArrayList
pub fn readArg(alloc: Allocator) !?ArrayList(u8) {
    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    if (args.len < 2) {
        return null;
    }

    var arg = ArrayList(u8).init(std.heap.page_allocator);
    try arg.appendSlice(args[1]);

    return arg;
}

/// A simple argument reader to
pub const ArgReader = struct {
    allocator: Allocator,
    args: ?[][:0]u8 = null,
    current: usize = 0,

    pub fn init(allocator: Allocator) ArgReader {
        return .{ .allocator = allocator };
    }

    pub fn read(self: *ArgReader) !*ArgReader {
        self.args = try std.process.argsAlloc(self.allocator);
        return self;
    }

    pub fn peek(self: *ArgReader) ?[:0]u8 {
        if (self.args == null) {
            return null;
        }
        const args = self.args.?;
        if (self.current >= args.len) {
            return null;
        }
        return args[self.current];
    }

    pub fn next(self: *ArgReader) ?[:0]u8 {
        if (self.args == null) {
            return null;
        }
        const args = self.args.?;
        if (self.current >= args.len) {
            return null;
        }
        const arg = args[self.current];
        self.current += 1;
        return arg;
    }

    pub fn deinit(self: *ArgReader) void {
        if (self.args) |args| {
            std.process.argsFree(self.allocator, args);
        }
    }
};

const t = std.testing;

test "ArgReader init/deinit" {
    var reader = ArgReader.init(t.allocator);
    defer reader.deinit();
}

test "read empty args" {
    const data: ?[][:0]u8 = &.{};
    var reader = ArgReader{
        .allocator = t.allocator,
        .args = data,
        .current = 0,
    };
    try t.expectEqual(null, reader.peek());
    try t.expectEqual(null, reader.next());
}

test "read single arg" {
    const arg_str = "arg1\x00";
    const data = try _test_input_args(arg_str);
    var reader = ArgReader{
        .allocator = t.allocator,
        .args = data,
        .current = 0,
    };
    try t.expectEqualStrings("arg1", reader.peek().?);
    try t.expectEqualStrings("arg1", reader.next().?);
    try t.expectEqual(null, reader.peek());
    try t.expectEqual(null, reader.next());
}

test "read multiple args" {
    const arg_str = "arg1\x00arg2\x00arg3\x00";
    const data = try _test_input_args(arg_str);
    var reader = ArgReader{
        .allocator = t.allocator,
        .args = data,
        .current = 0,
    };
    try t.expectEqualStrings("arg1", reader.peek().?);
    try t.expectEqualStrings("arg1", reader.next().?);
    try t.expectEqualStrings("arg2", reader.peek().?);
    try t.expectEqualStrings("arg2", reader.next().?);
    try t.expectEqualStrings("arg3", reader.peek().?);
    try t.expectEqualStrings("arg3", reader.next().?);
    try t.expectEqual(null, reader.peek());
    try t.expectEqual(null, reader.next());
}

test "multiple attempts to read past the end" {
    const arg_str = "arg1\x00";
    const data = try _test_input_args(arg_str);
    var reader = ArgReader{
        .allocator = t.allocator,
        .args = data,
        .current = 0,
    };
    try t.expectEqualStrings("arg1", reader.peek().?);
    try t.expectEqualStrings("arg1", reader.next().?);
    // attempt #1
    try t.expectEqual(null, reader.peek());
    try t.expectEqual(null, reader.next());
    // attempt #2
    try t.expectEqual(null, reader.peek());
    try t.expectEqual(null, reader.next());
}

test "it's an iterator too!" {
    const arg_str = "arg1\x00arg2\x00arg3\x00";
    const data = try _test_input_args(arg_str);
    var reader = ArgReader{
        .allocator = t.allocator,
        .args = data,
        .current = 0,
    };
    var i: u8 = 1;
    while (reader.next()) |arg| {
        const buf = "arg" ++ [_]u8{i + 48};
        try t.expectEqualStrings(buf, arg);
        i += 1;
    }
}

fn _test_input_args(input: []const u8) ![][:0]u8 {
    _ = &input;
    // Leak the memory for the args (okay for testing)
    var out = ArrayList([:0]u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    var prev: usize = 0;
    for (input, 0..) |c, i| {
        if (c == 0 and i > prev) {
            try out.append(@constCast(input[prev..i :0]));
            prev = i + 1;
        }
    }
    return out.items;
}
