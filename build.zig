const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "magics",
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);
    const lib_mod = b.addModule("magics", .{
        .source_file = .{ .path = "src/lib.zig" },
    });

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/lib.zig" },
        .target = target,
        .optimize = optimize,
    });
    const unit_tests_runner = b.addRunArtifact(unit_tests);
    unit_tests_runner.has_side_effects = true;

    // Creates a step for integration testing. This only builds the test
    // executable but does not run it.
    const integration_tests = b.addTest(.{
        .root_source_file = .{ .path = "integration_tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    integration_tests.addModule("magics", lib_mod);
    const integration_tests_runner = b.addRunArtifact(integration_tests);
    integration_tests_runner.has_side_effects = true;

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&unit_tests_runner.step);
    test_step.dependOn(&integration_tests_runner.step);
}
