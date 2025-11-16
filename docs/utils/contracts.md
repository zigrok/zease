# contracts

**Source:** [`src/utils/contracts.zig`](../../src/utils/contracts.zig)

Compile-time type validation utilities with **zero runtime cost**.

## implementsContract

Validates that a type implements a contract interface at compile time. Emits a single comprehensive compile error listing all violations if the contract is not satisfied.

### Purpose

Use this to enforce interface contracts at compile time with zero runtime overhead. Perfect for generic code that needs to ensure types meet specific requirements.

### Quick Example

```zig
const zease = @import("zease");
const implementsContract = zease.utils.contracts.implementsContract;

// Define a contract interface
const LoggerContract = struct {
    // Required function: log messages with a level
    log: *const fn (self: *Self, level: LogLevel, message: []const u8) void,
    // Required data field: configuration
    config: LogConfig,
};

// Implementation with concrete types
const FileLogger = struct {
    config: LogConfig,
    file_handle: std.fs.File,

    const Self = @This();

    pub fn log(self: *Self, level: LogLevel, message: []const u8) void {
        _ = self.file_handle.write(message) catch return;
    }
};

// Validate at compile time - compile error if contract not satisfied
comptime {
    implementsContract(LoggerContract, FileLogger);
}
```

### Detailed Example: Generic Repository Pattern

Here's a complete example showing how to use contracts with generic code:

```zig
const std = @import("std");
const zease = @import("zease");
const implementsContract = zease.utils.contracts.implementsContract;

// Define a repository contract
const RepositoryContract = struct {
    // Required methods
    save: *const fn (self: *Self, id: u32, data: []const u8) anyerror!void,
    load: *const fn (self: *Self, id: u32) anyerror![]const u8,
    delete: *const fn (self: *Self, id: u32) anyerror!void,

    // Required data fields
    allocator: std.mem.Allocator,
    name: []const u8,
};

// Concrete implementation: In-memory repository
const MemoryRepository = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    storage: std.AutoHashMap(u32, []const u8),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Self {
        return .{
            .allocator = allocator,
            .name = name,
            .storage = std.AutoHashMap(u32, []const u8).init(allocator),
        };
    }

    pub fn save(self: *Self, id: u32, data: []const u8) !void {
        const owned = try self.allocator.dupe(u8, data);
        try self.storage.put(id, owned);
    }

    pub fn load(self: *Self, id: u32) ![]const u8 {
        return self.storage.get(id) orelse error.NotFound;
    }

    pub fn delete(self: *Self, id: u32) !void {
        if (self.storage.fetchRemove(id)) |entry| {
            self.allocator.free(entry.value);
        }
    }
};

// Generic function that works with any repository implementation
fn processData(comptime Repo: type, repo: *Repo, id: u32) !void {
    // Validate contract at compile time
    comptime implementsContract(RepositoryContract, Repo);

    // Now we can safely use the contract methods
    const data = try repo.load(id);
    std.debug.print("Loaded from {s}: {s}\n", .{ repo.name, data });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var repo = MemoryRepository.init(allocator, "cache");
    defer repo.storage.deinit();

    try repo.save(1, "Hello, World!");
    try processData(MemoryRepository, &repo, 1);
}
```

### Features

- **Zero runtime cost** - all checks happen at compile time
- Validates both functions and data fields
- Checks function signatures match exactly
- Single comprehensive compile error listing all violations
- Works with generic types and complex interfaces

### Contract Definition

A contract is a struct type where:
- **Function fields**: Type must be a function pointer (`*const fn(...)`) - validates the target has a matching function declaration
- **Data fields**: Any non-function type - validates the target struct has a matching field with the same type

### Understanding Validation Errors

When a type doesn't satisfy the contract, you get a detailed compile error:

```
[RepositoryContract] Contract violations for target BrokenRepository:
  • missing function 'delete'
  • function 'load' has type fn(*BrokenRepository, u32) ![]u8; expected fn(*BrokenRepository, u32) ![]const u8
  • missing field 'name'
  • field 'allocator' has type std.mem.Allocator; expected std.heap.ArenaAllocator
```

This tells you exactly what's wrong:
- Missing required functions or fields
- Type mismatches (including const qualifiers and error unions)
- Return type differences

### API Reference

```zig
pub fn implementsContract(comptime Contract: type, comptime Target: type) void
```

**Parameters:**
- `Contract`: A struct type defining the required interface
- `Target`: The type to validate against the contract

**Behavior:**
- Succeeds silently if contract is satisfied
- Emits `@compileError` with detailed violation list if contract is not satisfied

### Use Cases

- Enforcing interfaces for generic types
- Validating plugin architectures
- Ensuring compatibility with trait-like patterns
- Documenting type requirements at compile time
