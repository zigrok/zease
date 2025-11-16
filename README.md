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

### 🔧 Utils

Utilities for common tasks including compile-time validation and formatting.

| Utility | Description | Docs |
|---------|-------------|------|
| **contracts** | Contract verification and validation at compile time | [📖 View](docs/utils/contracts.md) |
| **print** | .zon serialization and compile-time string formatting utilities | [📖 View](docs/utils/print.md) |

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

