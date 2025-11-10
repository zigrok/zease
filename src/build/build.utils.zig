const std = @import("std");

// ===================================================================
// 🎯 ZIG BUILD UTILITY SYSTEM
// ===================================================================

// #region Type Definitions
pub const DependencySpec = struct {
    name: []const u8,
    // If true, the dependency name will be suffixed with the target OS and architecture, i.e "dawn_windows_x86_64"
    // this makes it possible to specify platform-specific dependencies, like if binaries are included in the package.
    is_target_specific: bool = false,
    skippable: bool = false,
    required_os: ?[]const std.Target.Os.Tag = null,
};

pub const DependencyResult = struct {
    name: []const u8,
    resolved_name: []const u8,
    status: Status,
    dependency: ?*std.Build.Dependency = null,

    pub const Status = enum {
        satisfied,
        skipped,
        missing,
    };
};

pub const DependencyCheckSummary = struct {
    results: []DependencyResult,
    total_count: usize,
    satisfied_count: usize,
    skipped_count: usize,
    missing_count: usize,

    pub fn allSatisfied(self: DependencyCheckSummary) bool {
        return self.missing_count == 0;
    }

    pub fn printSummary(self: DependencyCheckSummary) void {
        std.debug.print("\n📊 Dependency Check Summary:\n", .{});
        std.debug.print("   Total: {d} | ✅ Satisfied: {d} | ⏭️ Skipped: {d} | ❌ Missing: {d}\n", .{
            self.total_count,
            self.satisfied_count,
            self.skipped_count,
            self.missing_count,
        });

        for (self.results) |result| {
            const icon = switch (result.status) {
                .satisfied => "✅",
                .skipped => "⏭️",
                .missing => "❌",
            };
            std.debug.print("   {s} {s} → {s}\n", .{ icon, result.name, result.resolved_name });
        }
        std.debug.print("\n", .{});
    }
};
// #endregion Type Definitions

// #region Core Functions
pub fn getPlatformDependency(b: *std.Build, dep_prefix: []const u8, target: std.Target) []const u8 {
    return b.fmt("{s}_{s}_{s}", .{
        dep_prefix,
        @tagName(target.os.tag),
        @tagName(target.cpu.arch),
    });
}

pub fn checkDependencies(
    b: *std.Build,
    build_manifest: anytype,
    target: std.Target,
    specs: []const DependencySpec,
) DependencyCheckSummary {
    var results = b.allocator.alloc(DependencyResult, specs.len) catch |err| {
        std.debug.print("❌ Failed to allocate memory for dependency results: {}\n", .{err});
        std.process.exit(1);
    };

    var satisfied_count: usize = 0;
    var skipped_count: usize = 0;
    var missing_count: usize = 0;

    for (specs, 0..) |spec, i| {
        const resolved_name = if (spec.is_target_specific)
            getPlatformDependency(b, spec.name, target)
        else
            spec.name;

        if (spec.required_os) |required_os_tags| {
            var platform_supported = false;
            for (required_os_tags) |required_os| {
                if (target.os.tag == required_os) {
                    platform_supported = true;
                    break;
                }
            }

            if (!platform_supported and spec.skippable) {
                results[i] = DependencyResult{
                    .name = spec.name,
                    .resolved_name = resolved_name,
                    .status = .skipped,
                };
                skipped_count += 1;
                continue;
            }
        }

        if (dependencyExists(build_manifest, resolved_name)) {
            if (b.lazyDependency(resolved_name, .{})) |dep| {
                results[i] = DependencyResult{
                    .name = spec.name,
                    .resolved_name = resolved_name,
                    .status = .satisfied,
                    .dependency = dep,
                };
                satisfied_count += 1;
            } else {
                results[i] = DependencyResult{
                    .name = spec.name,
                    .resolved_name = resolved_name,
                    .status = .missing,
                };
                missing_count += 1;
            }
        } else {
            results[i] = DependencyResult{
                .name = spec.name,
                .resolved_name = resolved_name,
                .status = .missing,
            };
            missing_count += 1;
        }
    }

    return DependencyCheckSummary{
        .results = results,
        .total_count = specs.len,
        .satisfied_count = satisfied_count,
        .skipped_count = skipped_count,
        .missing_count = missing_count,
    };
}
// #endregion

// #region Target Validation
pub const TargetSpec = struct {
    os: ?std.Target.Os.Tag = null,
    arch: ?std.Target.Cpu.Arch = null,
};

pub fn requireTargets(target: std.Target, allowed: []const TargetSpec) void {
    var is_supported = false;
    for (allowed) |spec| {
        const os_match = spec.os == null or target.os.tag == spec.os.?;
        const arch_match = spec.arch == null or target.cpu.arch == spec.arch.?;

        if (os_match and arch_match) {
            is_supported = true;
            break;
        }
    }

    if (is_supported) {
        std.debug.print("✅ Target {s}-{s} is supported\n", .{ @tagName(target.cpu.arch), @tagName(target.os.tag) });
        return;
    }

    std.debug.print("❌ Unsupported target: {s}-{s}\n", .{ @tagName(target.cpu.arch), @tagName(target.os.tag) });
    std.debug.print("   Supported targets:\n", .{});
    for (allowed) |spec| {
        const arch_str = if (spec.arch) |a| @tagName(a) else "*";
        const os_str = if (spec.os) |o| @tagName(o) else "*";
        std.debug.print("     {s}-{s}\n", .{ arch_str, os_str });
    }
    std.process.exit(1);
}
// #endregion Target Validation

// #region Debug Utilities
pub fn printAvailableDependencies(build_manifest: anytype) void {
    std.debug.print("\n📦 Build Manifest Analysis:\n", .{});

    if (@hasField(@TypeOf(build_manifest), "name")) {
        std.debug.print("   Package: {any}\n", .{build_manifest.name});
    }

    if (@hasField(@TypeOf(build_manifest), "version")) {
        std.debug.print("   Version: {any}\n", .{build_manifest.version});
    }

    if (@hasField(@TypeOf(build_manifest), "dependencies")) {
        const deps = build_manifest.dependencies;
        const dep_names = comptime std.meta.fieldNames(@TypeOf(deps));

        std.debug.print("   Dependencies ({d}):\n", .{dep_names.len});
        inline for (dep_names) |name| {
            std.debug.print("     ✓ {s}\n", .{name});
        }
    } else {
        std.debug.print("   Dependencies: None\n", .{});
    }
    std.debug.print("\n", .{});
}
// #endregion Debug Utilities

// #region Internal Helpers
fn dependencyExists(build_manifest: anytype, dep_name: []const u8) bool {
    if (!@hasField(@TypeOf(build_manifest), "dependencies")) {
        return false;
    }

    const deps = build_manifest.dependencies;
    const dep_names = comptime std.meta.fieldNames(@TypeOf(deps));

    inline for (dep_names) |name| {
        if (std.mem.eql(u8, dep_name, name)) {
            return true;
        }
    }
    return false;
}
// #endregion Internal Helpers
