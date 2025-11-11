const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.addModule("zease", .{
        .root_source_file = b.path("src/zease.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = b.addModule("zease-build", .{
        .root_source_file = b.path("src/zease-build.zig"),
    });

    const lib = b.addLibrary(.{
        .name = "zease",
        .root_module = root_module,
        .linkage = .static,
    });

    b.installArtifact(lib);
    const tests = b.addTest(.{
        .root_module = root_module,
    });

    b.getInstallStep().dependOn(&tests.step);

    const test_run = b.addRunArtifact(tests);

    const run_step = b.step("run", "Run zease tests");
    run_step.dependOn(&test_run.step);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&test_run.step);
}
