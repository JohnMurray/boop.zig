const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// Takes a path to an input file (relative to the current working directory) and returns
/// the contents of the file an an array of lines (ArrayList of []u8).
/// Example usage:
///     const lines = try shared_lib.readLines(std.heap.page_allocator, input_file);
///     defer {
///         for (lines.items) |line| { std.hea.page_allcoator.free(line); }
///         lines.deinit();
///     }
///
/// ToDo: Wrap this into a struct for easier memory management
pub fn readLines(alloc: Allocator, path: []u8) !ArrayList([]u8) {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var input_stream = buf_reader.reader();
    var lines = ArrayList([]u8).init(alloc);

    // Assume we can read 1kb lines
    var buf: [1024]u8 = undefined;
    while (try input_stream.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        // allocate space to copy the line from the buffer
        var line_copy = try alloc.alloc(u8, line.len);
        @memcpy(line_copy[0..line.len], line);

        // Add the copy to our return list
        try lines.append(line_copy);
    }

    return lines;
}
