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

pub const ArgParser = struct {
    allocator: Allocator,
    options: ArrayList(option(undefined)) = undefined,

    // Add a flag to the parser. 'T' is used to determine the type of the flag and there are only certain supported
    // types. A destination must be provided to store the value of the flag. Strings aren't supported here. Use the
    // 'addStringFlag' method instead.
    pub fn addFlag(self: *ArgParser, comptime T: type, short: []const u8, long: []const u8, description: []const u8, destination: ?*T) !void {
        // _ = self;
        _ = short;
        _ = long;
        _ = description;
        // _ = destination;
        var op = comptime {
            if (@TypeOf(T) == i32) {
                // do something
                option(i32){
                    .allocator = self.allocator,
                    .receiver = destination.?,
                };
            } else {
                // do something else
            }
        };
        _ = &op;
    }

    // pub fn addStringFlag

    pub fn parse(self: *ArgParser) !void {
        var reader = ArgReader.init(self.allocator);
        defer reader.deinit();

        // TODO: iterate over the reader and parse the arguments
        try reader.read();
    }

    pub fn init(allocator: Allocator) ArgParser {
        var parser = .{ .allocator = allocator };
        parser.options = ArrayList(option(undefined)).init(allocator);
        return parser;
    }

    pub fn deinit(self: *ArgParser) void {
        self.options.deinit();
    }
};

//--------------------------------------------------------------------------------
// `option` struct

/// `option` is a generic struct for representing potential flag options. It is meant to hold
/// basic types (ints, bools, floats, strings). It does not work for more complex types (lists,
/// maps, structs, etc). The purpose is to encapsulate all individual flag operations such as
/// flag matching, parsing, and generating a description.
fn option(comptime T: type) type {
    return struct {
        allocator: Allocator,
        receiver: *T = undefined,
        length: usize = 0,

        // Flag names in the format of "--long-name" or "-s"
        long_name: ?ArrayList(u8) = null,
        short_name: ?ArrayList(u8) = null,

        const Self = @This();

        pub fn parse(self: *Self, arg: []const u8) !void {
            // Use the comptime type for the option to delegate to the correct parsing function
            comptime var parse_fn: *const fn ([]const u8, *T) anyerror!void = undefined;
            comptime {
                if (T == i32) {
                    parse_fn = parse_i32;
                } else {
                    // unsupported type
                    @compileError("Unsupported option type " ++ @typeName(T));
                }
            }
            try parse_fn(arg, self.receiver);
        }

        pub fn with_long_name(self: *Self, name: []const u8) !void {
            self.long_name = ArrayList(u8).init(self.allocator);
            try self.long_name.?.appendSlice(name);
        }

        pub fn with_short_name(self: *Self, name: []const u8) !void {
            self.short_name = ArrayList(u8).init(self.allocator);
            try self.short_name.?.appendSlice(name);
        }

        pub fn deinit(self: *Self) void {
            if (self.long_name) |name| {
                name.deinit();
            }
            if (self.short_name) |name| {
                name.deinit();
            }
        }
    };
}

test "i32 option" {
    const i32_op = option(i32);

    var receiver: i32 = 0;
    var op = i32_op{ .allocator = t.allocator, .receiver = &receiver };
    defer op.deinit();

    try op.with_short_name("-u");
    try op.with_long_name("--boop");
    try op.parse("64");

    try t.expectEqual(64, receiver);
}

//--------------------------------------------------------------------------------
// Parsing functions

fn parse_i32(arg: []const u8, dest: *i32) !void {
    var value: i32 = 0;
    for (arg) |c| {
        if (c < '0' or c > '9') {
            return error.InvalidInteger;
        }
        value = value * 10 + (c - '0');
    }
    dest.* = value;
}

//--------------------------------------------------------------------------------
// Input Argument Reader / Iterator

/// A simple argument reader to iterate over argument passed to a program.
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
