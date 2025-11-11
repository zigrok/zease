# 🚀 zease

> **Easy-to-use quality of life helpers, utilities, and types for Zig**

A work-in-progress collection of convenient helpers for Zig projects. Things are added as they're found useful or built for other projects.

---

## 📦 Installation

Add zease to your `build.zig.zon`:

```bash
zig fetch --save https://github.com/zigrok/zease/archive/<commit-hash>.tar.gz
```

Then in your `build.zig`:

```zig
const zease_dep = b.dependency("zease", .{
    .target = target,
    .optimize = optimize,
});

const zease_module = zease_dep.module("zease");
exe.root_module.addImport("zease", zease_module);
```

---

## � Documentation

### 🧵 Concurrency

Thread-safe data structures and utilities.

| Type | Description | Docs |
|------|-------------|------|
| **ConcurrentStringMap** | Thread-safe string-keyed hash map with automatic key management | [📖 View](docs/concurrency/ConcurrentStringMap.md) |

### 🏗️ Build

Build system utilities for dependency management and target validation.

| Utility | Description | Docs |
|---------|-------------|------|
| **build.utils** | Dependency checking, target validation, platform-specific helpers | [📖 View](docs/build/build.utils.md) |

### 🔧 Types

Compile-time type validation and utilities with zero runtime cost.

| Utility | Description | Docs |
|---------|-------------|------|
| **type_utils** | Contract verification, interface validation at compile time | [📖 View](docs/types/type_utils.md) |

---

## 🎯 Quick Examples

### ConcurrentStringMap

```zig
const zease = @import("zease");
const ConcurrentStringMap = zease.concurrency.ConcurrentStringMap;

var map = ConcurrentStringMap(i32).init(allocator);
defer map.deinit();

try map.put("key", 42);
const value = map.get("key"); // ?i32
```

### Type Utils

```zig
const implementsContract = zease.types.type_utils.implementsContract;

const WriterContract = struct {
    write: *const fn (self: *anyopaque, bytes: []const u8) anyerror!usize,
};

comptime {
    implementsContract(WriterContract, MyWriter);
}
```

### Build Utils

**Note:** `build.utils.zig` must be copied to your project to use in `build.zig` files. See [docs](docs/build/build.utils.md) for details.

```zig
const build_utils = @import("build.utils.zig");

const summary = build_utils.checkDependencies(b, @import("build_options"), target, &deps);
if (!summary.allSatisfied()) {
    std.process.exit(1);
}
```

---

## 🧪 Testing

```bash
zig build test
```

---

## 🤝 Contributing

Contributions welcome! Everything in zease must be **ZEASY** - we prioritize ease of use over raw performance.

📖 Read the [Contributing Guide](CONTRIBUTING.md) for details on our philosophy, code style, and submission process.

---

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

