const std = @import("std");
const Module = std.Build.Module;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod_boop = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_boop = b.addStaticLibrary(.{
        .name = "boop",
        .root_module = mod_boop,
    });

    b.installArtifact(lib_boop);

    const test_boop = b.addTest(.{
        .root_module = mod_boop,
    });
    const run_lib_unit_tests = b.addRunArtifact(test_boop);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    for ((getExampleFiles(b) catch @panic("Failed to get example files")).items) |name| {
        build_example(b, .{
            .name = name,
            .boop_lib = mod_boop,
            .target = target,
            .optimize = optimize,
        });
    }
}

const ExampleOpts = struct {
    name: []const u8,
    boop_lib: *Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

/// Build an example executable. There are a few assumptions made here:
///   - The example is located in the `examples` directory
///   - The example is a single file with the same name as the example
///     Example:
///       build_example(b, .{name = "cli"}) -> produces "example_cli" from "examples/cli.zig"
fn build_example(b: *std.Build, opts: ExampleOpts) void {
    const mod_example = b.createModule(.{
        .root_source_file = b.path(b.fmt("examples/{s}.zig", .{opts.name})),
        .target = opts.target,
        .optimize = opts.optimize,
    });

    mod_example.addImport("boop", opts.boop_lib);

    const exe_example = b.addExecutable(.{
        .name = b.fmt("example_{s}", .{opts.name}),
        .root_module = mod_example,
    });

    b.installArtifact(exe_example);
}

/// Returns an arraylist of all files in "exampes/" directory, which is a directory under the
/// current working directory.
fn getExampleFiles(b: *std.Build) !std.ArrayList([]u8) {
    var dir = try std.fs.cwd().openDir("examples", .{ .iterate = true });
    defer dir.close();
    var it = dir.iterate();

    var files = std.ArrayList([]u8).init(std.heap.page_allocator);

    while (try it.next()) |file| {
        if (file.kind != .file) {
            continue;
        }
        if (!std.mem.endsWith(u8, file.name, ".zig")) {
            continue;
        }

        try files.append(b.dupe(file.name[0..(file.name.len - 4)]));
    }

    return files;
}
