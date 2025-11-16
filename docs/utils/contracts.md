# contracts

**Source:** [`src/utils/contracts.zig`](../../src/utils/contracts.zig)

Compile-time contract validation with **zero runtime cost**.

## API

```zig
implementsContract(comptime Contract: type, comptime Target: type) void
implementsContractIgnoreFuncParams(comptime Contract: type, comptime Target: type, comptime check_params: bool) void
```

Validates that a target type satisfies a contract struct. Has two signatures:
- **`implementsContract`**: Validates exact function signatures and field types
- **`implementsContractIgnoreFuncParams`**: Pass `check_params=false` to ignore function parameters/return types while still enforcing functions with matching names exist

## What's Validated

- **Fields**: Target must have fields with matching names and exact matching types (always strict)
- **Functions**: Target must have functions with matching names that are actual functions (not fields or other declarations)
- **Function signatures**: Parameters and return types only checked with `implementsContract` or when `check_params=true`

## Example

```zig
const Contract = struct {
    allocator: std.mem.Allocator,
    process: fn(*Self, []const u8) !void,
};

const StrictImpl = struct {
    allocator: std.mem.Allocator,
    pub fn process(self: *StrictImpl, data: []const u8) !void { ... }
};

const FlexibleImpl = struct {
    allocator: std.mem.Allocator,
    pub fn process(self: *FlexibleImpl, x: u64, y: bool) !u32 { ... } // Different signature
};

comptime {
    implementsContract(Contract, StrictImpl); // ✓ Exact match required
    implementsContractIgnoreFuncParams(Contract, FlexibleImpl, false); // ✓ Only checks process exists as function
}
```

## Contract Definition

A contract is a struct where:
- **Function fields**: `fn(...)` type - validates target has matching function
- **Data fields**: Any non-function type - validates target has matching field

## Validation Errors

```
[Contract] Contract violations for target Impl:
  • missing function 'process'
  • function 'load' has type fn(*Impl) ![]u8; expected fn(*Impl) ![]const u8
  • missing field 'allocator'
```

### Use Cases

- Enforcing contracts for generic types
- Validating plugin architectures
- Ensuring compatibility with trait-like patterns
- Documenting type requirements at compile time
- Duck-typed contracts with flexible function signatures (using `implementsContractIgnoreFuncParams`)
