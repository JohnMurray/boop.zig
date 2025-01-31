const std = @import("std");

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
}
