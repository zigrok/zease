# print

**Source:** [`src/utils/print.zig`](../../src/utils/print.zig)

Compile-time string building and .zon serialization utilities for debugging and code generation.

## Overview

.zon serialization utilities for converting any Zig value to `.zon` format for debugging, config generation, or data inspection.

---

## .zon Serialization### printZon

```zig
pub fn printZon(value: anytype) !void
```

Prints any Zig value as .zon-formatted output to debug console.

A convenience wrapper around `dumpZonAlloc` that handles memory management automatically using an arena allocator.

**Example:**

```zig
const Config = struct {
    host: []const u8,
    port: u16,
    enabled: bool,
};

const config = Config{
    .host = "localhost",
    .port = 8080,
    .enabled = true,
};

try printZon(config);
```

**Output:**

```zon
.{
  .host = "localhost",
  .port = 8080,
  .enabled = true,
}
```

### dumpZonAlloc

```zig
pub fn dumpZonAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8
```

Serializes any Zig value to a .zon-formatted string.

**Parameters:**
- `allocator` - Memory allocator for the returned string
- `value` - Any Zig value to serialize

**Returns:** Allocated string containing .zon representation

**Caller Responsibility:** Must free the returned slice using the provided allocator

**Example:**

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

const data = .{
    .name = "zease",
    .version = "0.1.0",
    .dependencies = .{
        .shimizu = "1.2.0",
    },
};

const zon = try dumpZonAlloc(allocator, data);
defer allocator.free(zon);

std.debug.print("{s}\n", .{zon});
```

---

## Supported Types

The .zon serialization system supports the following Zig types:

### Primitives

| Type | .zon Representation | Example |
|------|---------------------|---------|
| `bool` | `true` or `false` | `true` |
| `int`, `comptime_int` | Decimal number | `42` |
| `float`, `comptime_float` | Decimal with fraction | `3.14159` |
| `void` | `void` | `void` |
| `null` | `null` | `null` |
| `undefined` | `undefined` | `undefined` |
| `type` | `type(.TypeName)` | `type(.u32)` |

### Collections

| Type | .zon Representation | Example |
|------|---------------------|---------|
| Struct | `.{ .field = value, ... }` | `.{ .x = 10, .y = 20 }` |
| Tuple | `.{ value, ... }` | `.{ 1, "two", true }` |
| Array | `.{ item, ... }` | `.{ 1, 2, 3 }` |
| Slice | `.{ item, ... }` | `.{ "a", "b", "c" }` |
| Vector | `.{ item, ... }` | `.{ 1.0, 2.0, 3.0 }` |

### Special Cases

| Type | .zon Representation | Example |
|------|---------------------|---------|
| `[N]u8` / `[]const u8` | String literal | `"hello"` |
| `[:0]const u8` | Null-terminated string | `"hello"` |
| Enum | `.tag` | `.active` |
| Tagged union | `.tag = payload` | `.ok = 42` |
| Error set | `error.Name` | `error.OutOfMemory` |
| Error union (ok) | Unwrapped payload | `42` |
| Error union (err) | `error.Name` | `error.FileNotFound` |
| Optional (some) | Unwrapped value | `"value"` |
| Optional (none) | `null` | `null` |
| Pointer (single) | `"ptr(0xaddress)"` | `"ptr(0x7fff1234)"` |
| Pointer (many/C) | `"ptr[*](0xaddress)"` | `"ptr[*](0x7fff5678)"` |

### String Escaping

String literals are properly escaped:

| Character | Escape Sequence |
|-----------|----------------|
| `\` | `\\` |
| `"` | `\"` |
| Newline | `\n` |
| Carriage return | `\r` |
| Tab | `\t` |
| Control chars (< 32 or 127) | `\xNN` (hex) |

---

## Complete Example

```zig
const std = @import("std");
const zease = @import("zease");
const printZon = zease.utils.print.printZon;
const dumpZonAlloc = zease.utils.print.dumpZonAlloc;

const ServerConfig = struct {
    host: []const u8,
    port: u16,
    tls: TlsConfig,
    endpoints: []const Endpoint,
};

const TlsConfig = struct {
    enabled: bool,
    cert_path: ?[]const u8,
};

const Endpoint = struct {
    path: []const u8,
    methods: []const []const u8,
};

pub fn main() !void {
    const config = ServerConfig{
        .host = "0.0.0.0",
        .port = 8443,
        .tls = .{
            .enabled = true,
            .cert_path = "/etc/ssl/cert.pem",
        },
        .endpoints = &.{
            .{ .path = "/api/v1/users", .methods = &.{ "GET", "POST" } },
            .{ .path = "/api/v1/auth", .methods = &.{"POST"} },
        },
    };

    // Quick debug output
    std.debug.print("Server configuration:\n", .{});
    try printZon(config);

    // Or get the string for further processing
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const zon_string = try dumpZonAlloc(gpa.allocator(), config);
    defer gpa.allocator().free(zon_string);

    // Write to file, send over network, etc.
    const file = try std.fs.cwd().createFile("config.zon", .{});
    defer file.close();
    try file.writeAll(zon_string);
}
```

**Output:**

```zon
.{
  .host = "0.0.0.0",
  .port = 8443,
  .tls = .{
    .enabled = true,
    .cert_path = "/etc/ssl/cert.pem",
  },
  .endpoints = .{
    .{
      .path = "/api/v1/users",
      .methods = .{
        "GET",
        "POST",
      },
    },
    .{
      .path = "/api/v1/auth",
      .methods = .{
        "POST",
      },
    },
  },
}
```

---

## Use Cases

### 1. Debugging Complex Data Structures

```zig
const result = try database.query("SELECT * FROM users");
try printZon(result); // See the complete structure
```

### 2. Generating Configuration Files

```zig
const config = buildConfiguration();
const zon = try dumpZonAlloc(allocator, config);
try std.fs.cwd().writeFile("generated.zon", zon);
```

### 3. Testing Output

```zig
test "config serialization" {
    const config = Config{ .port = 3000 };
    const zon = try dumpZonAlloc(testing.allocator, config);
    defer testing.allocator.free(zon);

    try testing.expectEqualStrings(
        \\.{
        \\  .port = 3000,
        \\}
    , zon);
}
```

---

## Implementation Notes

- **Zero runtime cost for `appendBulletPoint`**: All string concatenation happens at compile time
- **Memory management**: `printZon` uses a temporary arena allocator; `dumpZonAlloc` requires caller to free
- **Type support**: Unsupported types fall back to `{any}` formatting wrapped in string literals
- **Indentation**: 2 spaces per nesting level (configurable via `indent_step` constant)
- **Performance**: Suitable for debugging and tooling, not optimized for high-frequency serialization
