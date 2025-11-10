# ConcurrentStringMap

**Source:** [`src/concurrency/ConcurrentStringMap.zig`](../../src/concurrency/ConcurrentStringMap.zig)

A thread-safe string-keyed hash map with automatic key memory management.

## Features

- Thread-safe operations with mutex-based locking
- Automatic key duplication and cleanup
- Zero-copy reads where possible
- Comprehensive test coverage with multi-threaded tests

## Usage

```zig
const zease = @import("zease");
const ConcurrentStringMap = zease.concurrency.ConcurrentStringMap;

var map = ConcurrentStringMap(i32).init(allocator);
defer map.deinit(); // Automatically frees all keys

// Thread-safe operations
try map.put("key", 42);           // Keys are automatically duplicated
const value = map.get("key");     // Returns ?i32
const exists = map.contains("key");

// Atomic update
const prev = try map.fetchPut("key", 100); // Returns previous value

// Safe in-place mutation
_ = map.withValue("key", struct {
    fn increment(val: *i32) void {
        val.* += 1;
    }
}.increment);

// Thread-safe iteration
map.forEach(struct {
    fn print(_: []const u8, val: *i32) void {
        std.debug.print("Value: {}\n", .{val.*});
    }
}.print);

// Remove operations
_ = map.remove("key");                // Returns bool
const removed = map.fetchRemove("key"); // Returns ?V
```

## API Reference

### `init(allocator: Allocator) Self`

Create a new concurrent map. The allocator must outlive the map.

### `deinit(self: *Self) void`

Deinitialize the map storage. Frees all owned keys; values are caller-owned.

### `put(self: *Self, key: []const u8, value: V) Allocator.Error!void`

Insert or overwrite. Makes a copy of the key string.

### `fetchPut(self: *Self, key: []const u8, value: V) Allocator.Error!?V`

Insert and return previous value if any. Makes a copy of the key string if it's new.

### `get(self: *Self, key: []const u8) ?V`

Get a copy of the value. Thread-safe read operation.

### `contains(self: *Self, key: []const u8) bool`

Check if a key exists in the map.

### `remove(self: *Self, key: []const u8) bool`

Remove and report whether a value was present. Frees the owned key.

### `fetchRemove(self: *Self, key: []const u8) ?V`

Remove and return the previous value, if any. Frees the owned key.

### `withValue(self: *Self, key: []const u8, func: fn (*V) void) bool`

Safe in-place mutation under the lock. No pointer escapes after unlock. Returns `true` if the key was found, `false` otherwise.

### `forEach(self: *Self, func: fn ([]const u8, *V) void) void`

Locked iteration callback. Any mutation must happen via the provided pointer while still under lock.

## Thread Safety

All operations are protected by a mutex. The map is safe to use from multiple threads concurrently. Keys are automatically duplicated and owned by the map, so they can be freed immediately after calling `put` or `fetchPut`.

## Memory Management

- **Keys**: Automatically duplicated on insert and freed on remove/deinit
- **Values**: Caller-owned, not freed by the map
- **Map**: Call `deinit()` to free all internal storage and owned keys
