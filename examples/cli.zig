const std = @import("std");
const boop = @import("boop");

const cli = boop.cli;

pub fn main() !void {
    // Construct our parser with a name and description
    var parser = cli.ArgParser.init(std.heap.page_allocator, .{
        .cli_name = "cli-example",
        .cli_description = "A small program to show off as an exmaple for boop.cli",
    });
    defer parser.deinit();

    // Define the destination for storing flag results
    var hello_num: i32 = 1;
    var print_goodbye: bool = false;

    // Define our flags
    try parser.addFlag(i32, "-n", "--num", "Number of times to say hello", &hello_num);
    try parser.addFlag(bool, "-g", "--print-goodbye", "Should we also print goodbye?", &print_goodbye);

    // Attempt to parse the arguments. Handle the PrintHelp case and decide
    // what to do. Normally, you just want to exit cleanly.
    parser.parse() catch |err| {
        if (err == error.PrintHelp) {
            return;
        }
        return err;
    };

    // Perform any additional validation on the arguments here, after parsing

    // Print hello `hello_num` times and print goodbye if requested
    for (0..@abs(hello_num)) |_| {
        std.debug.print("Hello!\n", .{});
    }
    if (print_goodbye) {
        std.debug.print("Goodbye!\n", .{});
    }
}
