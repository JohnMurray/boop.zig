# boop.cli

A minimal command line argument parsing utility in the style of Go's `flag` package.

### Usage

```zig
const std = @import("std");
const boop = @import("boop");
const cli = boop.cli;

var favorite_number: i32 = 0;
var verbose: bool = false;

fn main() !void {
    var parser = cli.ArgParser.init(std.heap.page_allocator);
    defer parser.deinit();

    try parser.addFlag(i32, "-n", "--favorite-number", "Your ABSOLUTE favorite (integer) number", &favorite_number);
    try parser.addFlag(bool, "-v", "--verbose", "Verbose messages", &verbose);

    try parser.parse();

    if (verbose) {
        std.debug.print("Your favorite number is {d}\n", .{favorite_number});
    }
}
```
