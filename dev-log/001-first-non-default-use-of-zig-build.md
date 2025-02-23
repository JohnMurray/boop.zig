# First non-default use of `build.zig`
## 2025-02-22

## Scratching an itch

I wanted to create a directory of examples for any small library bits that I'm writing in
`boop`. I figured that each example should just be a single file, otherwise the example is
more complicated than I'd be willing to put together. So I made my first example file in
`examples/cli.zig` to make a small demo for [`src/cli.zig`][cli_src] and then wrote up the
minimal bits I needed in `build.zig`

```zig
    const cli_example = b.createModule(.{
        .root_source_file = b.path("examples/cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    const cli_example = b.addExecutable(.{
        .name = "example_cli",
        .root_module = cli_example,
    });

    b.installArtifact(cli_example);
```

Easy enough. But then I got to thinking. When I have more examples, am I going to have to come
back into my `build.zig` and copy/pasta this every time? I don't want to do that. But this is
just regular Zig, right? I can extract this out into a separate method.

```zig
const ExampleOpts = struct {
    name: []const u8,
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

    const exe_example = b.addExecutable(.{
        .name = b.fmt("example_{s}", .{opts.name}),
        .root_module = mod_example,
    });

    b.installArtifact(exe_example);
}
```

Now the build can be simplified to adding a single line for each new examples. Yes!

```zig
pub fn build(b: *std.Build) void {
  // ...

  build_example(b, .{.name = "cli", .target = target, .optimize = optimize});
}
```

### More automation?

This was great, but if this is just regular Zig, then mayb I can just iterate over the `examples`
directory and dynamically generate executables? Yes, apparently.

```zig
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

pub fn build(b: *std.Build) void {
  // ...

  for ((getExampleFiles(b) catch @panic("Failed to get example files")).items) |name| {
      build_example(b, .{ .name = name, .target = target, .optimize = optimize });
  }
}
```

Great, now each file in the `examples` directory is assumed to be a single-file binary and new examples
do not require changes to the build file.

### Reflections

Writing this code and making this work for my very silly problem felt powerful. Is the Zig build system
a super power? I've written build-system plugins and maintained multiple complex build systems in various
languages, but this felt the most straight-forward and natural. At least in the small, this feels like a
super power.

However, my day job working on/around the build system for a large monorepo supporting multiple languages
tells me that this might be a curse in the large. Would a build system with this level of flexibility and
power scale well to hundreds or thousands of developers? Or does scalability in this regard require new
layers of abstraction?

History tells me this is cursed for scalable software, but maybe that's not the goal. In the small, this
feels wonderful, and I'm not sure I'd change a thing.

  [cli_src]: https://github.com/JohnMurray/boop.zig/blob/main/src/cli.zig
