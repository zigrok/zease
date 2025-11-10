# type_utils

**Source:** [`src/types/type_utils.zig`](../../src/types/type_utils.zig)

Compile-time type validation utilities with **zero runtime cost**.

## implementsContract

Validates that a type implements a contract interface at compile time. Emits a single comprehensive compile error listing all violations if the contract is not satisfied.

### Purpose

Use this to enforce interface contracts at compile time with zero runtime overhead. Perfect for generic code that needs to ensure types meet specific requirements.

### Usage

```zig
const zease = @import("zease");
const implementsContract = zease.types.type_utils.implementsContract;

// Define a contract
const WriterContract = struct {
    write: *const fn (self: *anyopaque, bytes: []const u8) anyerror!usize,
    flush: *const fn (self: *anyopaque) anyerror!void,
};

// Validate at compile time
const MyWriter = struct {
    pub fn write(self: *anyopaque, bytes: []const u8) !usize {
        _ = self;
        return bytes.len;
    }

    pub fn flush(self: *anyopaque) !void {
        _ = self;
    }
};

comptime {
    implementsContract(WriterContract, MyWriter);
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

### Error Output Example

If validation fails, you get a clear compile error:

```
[WriterContract] Contract violations for target MyWriter:
  • missing function 'flush'
  • function 'write' has type fn(*MyWriter, []const u8) !usize; expected fn(*anyopaque, []const u8) !usize
```

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
