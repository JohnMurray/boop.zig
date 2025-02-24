const std = @import("std");
const t = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// ArgParser is a simple command line argument parser in the style of Go's flag package. It is
/// minimal in the sense that it may not support all features you would find in a standalone
/// argument parsing library.
///
/// See docs/cli.md for more information on how to use this utility.
pub const ArgParser = struct {
    allocator: Allocator,

    cli_name: ?[]const u8 = null,
    cli_description: ?[]const u8 = null,

    // If the user doesn't provide a CLI name, we can discover the name when parsing initial arguments
    found_name: ?[]const u8 = null,

    option_i32: ArrayList(option(i32)) = undefined,
    option_bool: ArrayList(option(bool)) = undefined,

    // Optional reader assigned as a field to allow for easier testing. Otherwise this could simply be
    // a local variable in the 'parse' function.
    reader: ?ArgReader = null,

    /// Additional initialization options for ArgParser.init
    pub const InitOptions = struct {
        /// The name of the program, to be used in the help output
        /// If not provided, the program name will be discovered from the first argument
        cli_name: ?[]const u8 = null,
        /// A description of the program, to be used in the help output
        cli_description: ?[]const u8 = null,
    };

    // Add a flag to the parser. 'T' is used to determine the type of the flag and there are only certain supported
    // types. A destination must be provided to store the value of the flag. Strings aren't supported here. Use the
    // 'addStringFlag' method instead.
    pub fn addFlag(self: *ArgParser, comptime T: type, short: []const u8, long: []const u8, description: []const u8, destination: *T) !void {
        var op = option(T){
            .allocator = self.allocator,
            .receiver = destination,
        };
        try op.with_long_name(long);
        try op.with_short_name(short);
        try op.with_description(description);

        if (T == i32) {
            try self.option_i32.append(op);
        } else if (T == bool) {
            try self.option_bool.append(op);
        } else {
            // unsupported type
            @compileError("Unsupported option type " ++ @typeName(T));
        }
    }

    pub fn parse(self: *ArgParser) !void {
        if (self.reader == null) {
            self.reader = ArgReader.init(self.allocator);
        }

        // iterate over the reader and parse the arguments
        try self.reader.?.read();
        var i: usize = 0;
        while (self.reader.?.peek() != null) : (i += 1) {
            if (i == 0) {
                // The first argument is the program name
                self.found_name = self.reader.?.next();
                continue;
            }

            if (isHelpFlag(self.reader.?.peek().?)) {
                self.printHelp();
                return error.PrintHelp;
            }
            if (try self.tryParseOption(i32) or try self.tryParseOption(bool)) {
                // we've parsed an option, continue to the next argument
                _ = self.reader.?.next();
                continue;
            } else {
                // we've found a non-option argument, we're done
                break;
            }
        }
        // TODO: handle the remaining, non-option arguments
    }

    fn tryParseOption(self: *ArgParser, comptime T: type) !bool {
        if (self.reader == null or self.reader.?.peek() == null) {
            // Return true to mean that we're done rather than false which
            // would indicate some type of error.
            return true;
        }

        // Q: Is there an easy way to use comptime to construct the right field name?
        var option_list: []option(T) = undefined;
        if (T == i32) {
            option_list = self.option_i32.items;
        } else if (T == bool) {
            option_list = self.option_bool.items;
        } else {
            // unsupported type
            @compileError("Unsupported option type " ++ @typeName(T));
        }

        const arg = self.reader.?.peek().?;

        // If the arg contains an '=' sign, we need to split the arg into the flag and value
        var flag: []const u8 = undefined;
        var value: ?[]const u8 = null;
        const split = std.mem.indexOf(u8, arg, "=");
        if (split) |s| {
            flag = arg[0..s];
            value = arg[s + 1 ..];
        } else {
            flag = arg;
        }

        for (option_list) |*op| {
            if (op.match(flag)) {
                // We've matched on the arg. Now we need to process a value for the option. This will
                // either be the next argument or the value after the '=' sign.
                var argValue: ?[]const u8 = null;
                if (value) |v| {
                    argValue = v;
                } else {
                    // There was no value after the '=' sign, so we need to advance to the next argument
                    _ = self.reader.?.next();
                    argValue = self.reader.?.peek();
                }

                if (argValue == null) {
                    // No args found, but we were expecting at least 1
                    std.log.err("Argument missing for option {s}", .{arg});
                    return error.MissingArgument;
                }
                try op.parse(argValue.?);
                return true;
            }
        }

        return false;
    }

    fn isHelpFlag(arg: []const u8) bool {
        return std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h");
    }

    pub fn printHelp(self: *ArgParser) void {
        std.Progress.lockStdErr();
        defer std.Progress.unlockStdErr();
        const stderr = std.io.getStdErr().writer();

        var name: []const u8 = "PROGRAM";
        if (self.cli_name) |n| {
            name = n;
        } else if (self.found_name) |n| {
            name = n;
        }

        stderr.print("Usage for {s}\n", .{name}) catch {};
        if (self.cli_description) |desc| {
            stderr.print("\n{s}\n", .{desc}) catch {};
        }
        stderr.print("\nOptions:\n", .{}) catch {};
        self.printOptionHelp(i32, stderr);
        self.printOptionHelp(bool, stderr);
    }

    fn printOptionHelp(self: *ArgParser, comptime T: type, writer: std.fs.File.Writer) void {
        var option_list: []option(T) = undefined;
        if (T == i32) {
            option_list = self.option_i32.items;
        } else if (T == bool) {
            option_list = self.option_bool.items;
        } else {
            // unsupported type
            @compileError("Unsupported option type " ++ @typeName(T));
        }

        for (option_list) |*op| {
            op.printHelp(writer);
        }
    }

    pub fn init(allocator: Allocator, options: InitOptions) ArgParser {
        return .{
            .allocator = allocator,
            .option_i32 = ArrayList(option(i32)).init(allocator),
            .option_bool = ArrayList(option(bool)).init(allocator),
            .cli_name = options.cli_name,
            .cli_description = options.cli_description,
        };
    }

    pub fn deinit(self: *ArgParser) void {
        for (self.option_i32.items) |*op| {
            op.deinit();
        }
        self.option_i32.deinit();
        for (self.option_bool.items) |*op| {
            op.deinit();
        }
        self.option_bool.deinit();
        if (self.reader) |*reader| {
            reader.deinit();
        }
    }
};

test "ArgParser smoke test" {
    var parser = ArgParser.init(t.allocator, .{});
    defer parser.deinit();

    const arg_str = "PROG\x00--boop\x0042\x00-y\x001\x00";
    const data = try _test_input_args(arg_str);
    parser.reader = ArgReader{
        .allocator = t.allocator,
        .args = data,
        .current = 0,
    };
    defer parser.reader = null;

    var dest: i32 = 0;
    var dest_bool: bool = undefined;

    try parser.addFlag(i32, "-b", "--boop", "number of times booped", &dest);
    try parser.addFlag(bool, "-y", "--yes", "yes is true", &dest_bool);

    try parser.parse();
    try t.expectEqual(42, dest);
    try t.expectEqual(true, dest_bool);
}

test "ArgParser --help" {
    var parser = ArgParser.init(t.allocator, .{});
    defer parser.deinit();

    const arg_str = "--help\x00";
    const data = try _test_input_args(arg_str);
    parser.reader = ArgReader{
        .allocator = t.allocator,
        .args = data,
        .current = 0,
    };
    defer parser.reader = null;

    try parser.parse();
}

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
        description: ?ArrayList(u8) = null,

        const Self = @This();

        fn parse(self: *Self, arg: []const u8) !void {
            // Use the comptime type for the option to delegate to the correct parsing function
            comptime var parse_fn: *const fn ([]const u8, *T) anyerror!void = undefined;
            comptime {
                if (T == i32) {
                    parse_fn = parse_i32;
                } else if (T == bool) {
                    parse_fn = parse_bool;
                } else {
                    // unsupported type
                    @compileError("Unsupported option type " ++ @typeName(T));
                }
            }
            try parse_fn(arg, self.receiver);
        }

        fn with_long_name(self: *Self, name: []const u8) !void {
            self.long_name = ArrayList(u8).init(self.allocator);
            try self.long_name.?.appendSlice(name);
        }

        fn with_short_name(self: *Self, name: []const u8) !void {
            self.short_name = ArrayList(u8).init(self.allocator);
            try self.short_name.?.appendSlice(name);
        }

        fn with_description(self: *Self, desc: []const u8) !void {
            self.description = ArrayList(u8).init(self.allocator);
            try self.description.?.appendSlice(desc);
        }

        fn match(self: *Self, arg: []const u8) bool {
            if (self.long_name) |name| {
                if (std.mem.eql(u8, name.items, arg)) {
                    return true;
                }
            }
            if (self.short_name) |name| {
                if (std.mem.eql(u8, name.items, arg)) {
                    return true;
                }
            }

            return false;
        }

        fn printHelp(self: *Self, writer: std.fs.File.Writer) void {
            if (self.long_name) |name| {
                writer.print("  {s}", .{name.items}) catch {};
                if (self.short_name != null) {
                    writer.print("|", .{}) catch {};
                }
            }
            if (self.short_name) |name| {
                writer.print("{s}", .{name.items}) catch {};
            }
            if (self.description) |desc| {
                writer.print("  {s}", .{desc.items}) catch {};
            }
            writer.print("\n", .{}) catch {};
        }

        fn deinit(self: *Self) void {
            if (self.long_name) |name| {
                name.deinit();
            }
            if (self.short_name) |name| {
                name.deinit();
            }
            if (self.description) |desc| {
                desc.deinit();
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

    try op.parse("-64");
    try t.expectEqual(-64, receiver);
}

test "bool option" {
    const bool_op = option(bool);

    var receiver: bool = false;
    var op = bool_op{ .allocator = t.allocator, .receiver = &receiver };
    defer op.deinit();

    try op.with_short_name("-u");
    try op.with_long_name("--boop");

    try op.parse("true");
    try t.expectEqual(true, receiver);

    try op.parse("1");
    try t.expectEqual(true, receiver);

    try op.parse("false");
    try t.expectEqual(false, receiver);

    try op.parse("0");
    try t.expectEqual(false, receiver);
}

//--------------------------------------------------------------------------------
// Parsing functions

fn parse_i32(arg: []const u8, dest: *i32) !void {
    dest.* = try std.fmt.parseInt(i32, arg, 10);
}

fn parse_bool(arg: []const u8, dest: *bool) !void {
    if (std.mem.eql(u8, "true", arg) or std.mem.eql(u8, "1", arg)) {
        dest.* = true;
    } else if (std.mem.eql(u8, "false", arg) or std.mem.eql(u8, "0", arg)) {
        dest.* = false;
    } else {
        return error.InvalidArgument;
    }
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

    pub fn read(self: *ArgReader) !void {
        // only perform a read if we don't have data in args
        if (self.args == null) {
            self.args = try std.process.argsAlloc(self.allocator);
        }
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
        const buf = "arg" ++ [_]u8{i + '0'};
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
