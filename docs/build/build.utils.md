# build.utils

**Source:** [`src/build/build.utils.zig`](../../src/build/build.utils.zig)

Build system utilities for managing dependencies and target validation in Zig projects.

## 🎯 Primary Purpose

**Conditional lazy-fetching and compilation of platform-specific dependencies.**

The core value of `build.utils.zig` is enabling dependencies that are only fetched and compiled for specific platforms by encoding the target OS and architecture directly in the dependency key name (e.g., `dawn_windows_x86_64`, `native_lib_linux_aarch64`).

This allows you to:
- **Avoid fetching unnecessary dependencies** - Don't download Windows binaries on Linux builds
- **Skip compilation for wrong platforms** - Dependencies marked as skippable won't cause build failures on unsupported platforms
- **Ship platform-specific binaries** - Include pre-compiled libraries for each target in separate packages
- **Reduce build times** - Only process dependencies needed for the current target

The system leverages Zig's `lazyDependency()` which only fetches dependencies when they're actually used, combined with platform-aware dependency naming to achieve true conditional dependency resolution.

## ⚠️ Important: Usage in build.zig

**Due to Zig's build system limitations, `build.utils.zig` cannot be imported from dependencies in `build.zig` files.**

Zig's `@import()` requires compile-time string literals and cannot resolve dependency modules during build script compilation. This is a fundamental limitation - `@import()` paths must be known before any dependencies are fetched.

**You must copy `build.utils.zig` directly into your project to use it in `build.zig`:**

```zig
const build_utils = @import("build.utils.zig");
```

The zease dependency system works for your application code, but build scripts require file-based imports.

## Dependency Management

### checkDependencies

Check and validate project dependencies with detailed reporting.

```zig
const build_utils = @import("build.utils.zig");

const deps = [_]build_utils.DependencySpec{
    .{ .name = "raylib" },
    .{ .name = "zmath", .skippable = true },
    .{
        .name = "dawn",
        .is_target_specific = true,
        .required_os = &[_]std.Target.Os.Tag{.windows, .linux},
    },
};

const summary = build_utils.checkDependencies(
    b,
    @import("build_options"),
    target,
    &deps,
);

summary.printSummary();

if (!summary.allSatisfied()) {
    std.process.exit(1);
}
```

**Output:**
```
📊 Dependency Check Summary:
   Total: 3 | ✅ Satisfied: 2 | ⏭️ Skipped: 0 | ❌ Missing: 1
   ✅ raylib → raylib
   ✅ dawn → dawn_windows_x86_64
   ❌ zmath → zmath
```

### DependencySpec

Defines a dependency specification.

**Fields:**
- `name: []const u8` - Dependency name
- `is_target_specific: bool = false` - If true, name is suffixed with OS/arch (e.g., `dawn_windows_x86_64`)
- `skippable: bool = false` - If true, missing dependency won't cause failure
- `required_os: ?[]const std.Target.Os.Tag = null` - Limit dependency to specific operating systems

### DependencyCheckSummary

Result of dependency check operation.

**Methods:**
- `allSatisfied() bool` - Returns true if all non-skippable dependencies are present
- `printSummary() void` - Print formatted summary to debug output

**Fields:**
- `results: []DependencyResult` - Individual dependency check results
- `total_count: usize` - Total dependencies checked
- `satisfied_count: usize` - Successfully found dependencies
- `skipped_count: usize` - Skipped dependencies (wrong platform or marked skippable)
- `missing_count: usize` - Missing dependencies

## Target Validation

### requireTargets

Validate that the build target is supported, exit with error if not.

```zig
const allowed_targets = [_]build_utils.TargetSpec{
    .{ .os = .windows, .arch = .x86_64 },
    .{ .os = .linux, .arch = .x86_64 },
    .{ .os = .macos, .arch = .aarch64 },
};

build_utils.requireTargets(target, &allowed_targets);
```

**Output on success:**
```
✅ Target x86_64-windows is supported
```

**Output on failure:**
```
❌ Unsupported target: aarch64-linux
   Supported targets:
     x86_64-windows
     x86_64-linux
     aarch64-macos
```

### TargetSpec

Defines a target specification.

**Fields:**
- `os: ?std.Target.Os.Tag = null` - Operating system (null means any)
- `arch: ?std.Target.Cpu.Arch = null` - CPU architecture (null means any)

## Platform Utilities

### getPlatformDependency

Generate platform-specific dependency name.

```zig
const dep_name = build_utils.getPlatformDependency(b, "native_lib", target);
// Returns: "native_lib_windows_x86_64" on Windows x64
```

Useful for packages that ship platform-specific binaries.

## Debug Utilities

### printAvailableDependencies

Print all dependencies defined in build manifest for debugging.

```zig
build_utils.printAvailableDependencies(@import("build_options"));
```

**Output:**
```
📦 Build Manifest Analysis:
   Package: my_project
   Version: 0.1.0
   Dependencies (3):
     ✓ raylib
     ✓ zmath
     ✓ zig-gamedev
```

## Type Reference

### DependencyResult

Result of checking a single dependency.

**Fields:**
- `name: []const u8` - Original dependency name
- `resolved_name: []const u8` - Resolved name (may include platform suffix)
- `status: Status` - Check result status
- `dependency: ?*std.Build.Dependency` - Resolved dependency if satisfied

**Status enum:**
- `.satisfied` - Dependency found and loaded
- `.skipped` - Dependency skipped (platform mismatch or marked skippable)
- `.missing` - Dependency not found in manifest
