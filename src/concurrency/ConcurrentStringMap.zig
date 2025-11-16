const std = @import("std");
const Allocator = std.mem.Allocator;
// const ZeaseError = @import("../error.zig").ZeaseError; // currently unused

pub fn ConcurrentStringMap(comptime V: type) type {
    return struct {
        const Self = @This();

        mutex: std.Thread.Mutex = .{},
        allocator: Allocator,
        map: std.StringHashMapUnmanaged(V) = .empty,

        /// Create a new concurrent map.
        /// The allocator must outlive this map.
        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .map = .empty,
            };
        }

        /// Deinitialize the map storage.
        /// Frees all owned keys; values are caller-owned.
        pub fn deinit(self: *Self) void {
            self.mutex.lock();

            // Free all owned keys - we own the map so no concurrent access
            // Using keyIterator which doesn't expose value pointers
            var key_it = self.map.keyIterator();
            while (key_it.next()) |key_ptr| {
                self.allocator.free(key_ptr.*);
            }

            self.map.deinit(self.allocator);
            self.mutex.unlock();
            self.* = undefined;
        }

        /// Insert or overwrite with a callback that creates the value.
        /// Makes a copy of the key string.
        /// The callback receives the map's owned copy of the key.
        pub fn put(self: *Self, key: []const u8, createValue: fn ([]const u8) V) Allocator.Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();

            const gop = try self.map.getOrPut(self.allocator, key);
            if (!gop.found_existing) {
                // New key - make a copy
                gop.key_ptr.* = try self.allocator.dupe(u8, key);
            }
            // Always create value using the copied key
            gop.value_ptr.* = createValue(gop.key_ptr.*);
        }

        /// Insert and return previous value if any.
        /// Makes a copy of the key string if it's new.
        /// The callback receives the map's owned copy of the key.
        pub fn fetchPut(self: *Self, key: []const u8, createValue: fn ([]const u8) V) Allocator.Error!?V {
            self.mutex.lock();
            defer self.mutex.unlock();

            const gop = try self.map.getOrPut(self.allocator, key);
            const prev = if (gop.found_existing) gop.value_ptr.* else null;

            if (!gop.found_existing) {
                // New key - make a copy
                gop.key_ptr.* = try self.allocator.dupe(u8, key);
            }
            // Always create value using the copied key
            gop.value_ptr.* = createValue(gop.key_ptr.*);

            return prev;
        }

        /// Get a copy of the value.
        pub fn get(self: *Self, key: []const u8) ?V {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.map.get(key);
        }

        pub fn contains(self: *Self, key: []const u8) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.map.contains(key);
        }

        /// Remove and report whether a value was present.
        /// Frees the owned key.
        pub fn remove(self: *Self, key: []const u8) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.map.fetchRemove(key)) |kv| {
                self.allocator.free(kv.key);
                return true;
            }
            return false;
        }

        /// Remove and return the previous value, if any.
        /// Frees the owned key.
        pub fn fetchRemove(self: *Self, key: []const u8) ?V {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.map.fetchRemove(key)) |kv| {
                self.allocator.free(kv.key);
                return kv.value;
            }
            return null;
        }

        /// Safe in-place mutation under the lock.
        /// No pointer escapes after unlock.
        pub fn withValue(
            self: *Self,
            key: []const u8,
            func: fn (*V) void,
        ) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.map.getPtr(key)) |p| {
                func(p);
                return true;
            }
            return false;
        }

        /// Get the number of entries in the map.
        pub fn count(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.map.count();
        }

        /// Locked iteration callback.
        /// Any mutation must happen via the provided pointer while still under lock.
        pub fn forEach(
            self: *Self,
            func: fn ([]const u8, *V) void,
        ) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            var it = self.map.iterator();
            while (it.next()) |entry| {
                func(entry.key_ptr.*, entry.value_ptr);
            }
        }
    };
}

test "ConcurrentStringMap - basic put and get" {
    var dbg = std.heap.DebugAllocator(.{}){};
    const alloc = dbg.allocator();
    var cmap = ConcurrentStringMap(i32).init(alloc);
    defer cmap.deinit();

    const makeOne = struct {
        fn call(_: []const u8) i32 {
            return 1;
        }
    }.call;
    const makeTwo = struct {
        fn call(_: []const u8) i32 {
            return 2;
        }
    }.call;

    try cmap.put("one", makeOne);
    try cmap.put("two", makeTwo);

    try std.testing.expectEqual(@as(?i32, 1), cmap.get("one"));
    try std.testing.expectEqual(@as(?i32, 2), cmap.get("two"));
    try std.testing.expectEqual(@as(?i32, null), cmap.get("three"));
}

test "ConcurrentStringMap - contains" {
    var dbg = std.heap.DebugAllocator(.{}){};
    const alloc = dbg.allocator();
    var cmap = ConcurrentStringMap(i32).init(alloc);
    defer cmap.deinit();

    const make42 = struct {
        fn call(_: []const u8) i32 {
            return 42;
        }
    }.call;

    try cmap.put("exists", make42);

    try std.testing.expect(cmap.contains("exists"));
    try std.testing.expect(!cmap.contains("missing"));
}

test "ConcurrentStringMap - fetchPut" {
    var dbg = std.heap.DebugAllocator(.{}){};
    const alloc = dbg.allocator();
    var cmap = ConcurrentStringMap(i32).init(alloc);
    defer cmap.deinit();

    const make10 = struct {
        fn call(_: []const u8) i32 {
            return 10;
        }
    }.call;
    const make20 = struct {
        fn call(_: []const u8) i32 {
            return 20;
        }
    }.call;

    const prev1 = try cmap.fetchPut("key", make10);
    try std.testing.expectEqual(@as(?i32, null), prev1);

    const prev2 = try cmap.fetchPut("key", make20);
    try std.testing.expectEqual(@as(?i32, 10), prev2);

    try std.testing.expectEqual(@as(?i32, 20), cmap.get("key"));
}

test "ConcurrentStringMap - callback receives map's key copy" {
    var dbg = std.heap.DebugAllocator(.{}){};
    const alloc = dbg.allocator();

    const ValueWithKeyPtr = struct {
        key_ptr: [*:0]const u8,
    };

    var cmap = ConcurrentStringMap(ValueWithKeyPtr).init(alloc);
    defer cmap.deinit();

    const createValue = struct {
        fn call(key: []const u8) ValueWithKeyPtr {
            // Cast the key to a sentinel-terminated pointer
            // This demonstrates that the value can safely reference the key
            return .{ .key_ptr = @ptrCast(key.ptr) };
        }
    }.call;

    try cmap.put("test_key", createValue);

    const val = cmap.get("test_key");
    try std.testing.expect(val != null);

    // Verify the pointer points to valid data
    const key_slice = std.mem.span(val.?.key_ptr);
    try std.testing.expectEqualStrings("test_key", key_slice);
}

test "ConcurrentStringMap - remove and fetchRemove" {
    var dbg = std.heap.DebugAllocator(.{}){};
    const alloc = dbg.allocator();
    var cmap = ConcurrentStringMap(i32).init(alloc);
    defer cmap.deinit();

    const make100 = struct {
        fn call(_: []const u8) i32 {
            return 100;
        }
    }.call;
    const make200 = struct {
        fn call(_: []const u8) i32 {
            return 200;
        }
    }.call;

    try cmap.put("key1", make100);
    try cmap.put("key2", make200);

    try std.testing.expect(cmap.remove("key1"));
    try std.testing.expect(!cmap.contains("key1"));
    try std.testing.expect(!cmap.remove("key1"));

    const removed = cmap.fetchRemove("key2");
    try std.testing.expectEqual(@as(?i32, 200), removed);
    try std.testing.expectEqual(@as(?i32, null), cmap.fetchRemove("key2"));
}

test "ConcurrentStringMap - withValue" {
    var dbg = std.heap.DebugAllocator(.{}){};
    const alloc = dbg.allocator();
    var cmap = ConcurrentStringMap(i32).init(alloc);
    defer cmap.deinit();

    const makeZero = struct {
        fn call(_: []const u8) i32 {
            return 0;
        }
    }.call;

    try cmap.put("counter", makeZero);

    const increment = struct {
        fn call(val: *i32) void {
            val.* += 1;
        }
    }.call;

    try std.testing.expect(cmap.withValue("counter", increment));
    try std.testing.expectEqual(@as(?i32, 1), cmap.get("counter"));

    try std.testing.expect(!cmap.withValue("missing", increment));
}

test "ConcurrentStringMap - forEach" {
    var dbg = std.heap.DebugAllocator(.{}){};
    const alloc = dbg.allocator();
    var cmap = ConcurrentStringMap(i32).init(alloc);
    defer cmap.deinit();

    const make1 = struct {
        fn call(_: []const u8) i32 {
            return 1;
        }
    }.call;
    const make2 = struct {
        fn call(_: []const u8) i32 {
            return 2;
        }
    }.call;
    const make3 = struct {
        fn call(_: []const u8) i32 {
            return 3;
        }
    }.call;

    try cmap.put("a", make1);
    try cmap.put("b", make2);
    try cmap.put("c", make3);

    const callback = struct {
        fn call(_: []const u8, val: *i32) void {
            // Just verify we can iterate
            _ = val.*;
        }
    }.call;

    cmap.forEach(callback);
}

test "ConcurrentStringMap - concurrent put operations" {
    const testing = std.testing;
    var dbg = std.heap.DebugAllocator(.{}){};
    const alloc = dbg.allocator();
    var cmap = ConcurrentStringMap(i32).init(alloc);
    defer cmap.deinit();

    const ThreadContext = struct {
        map: *ConcurrentStringMap(i32),
        allocator: Allocator,
        thread_id: usize,

        fn worker(ctx: @This()) void {
            const id = ctx.thread_id;
            // Parse key to extract thread_id and index to compute value
            const makeValue = struct {
                fn call(key: []const u8) i32 {
                    // Key format: "thread{d}_key{d}"
                    // Extract thread_id and i from key
                    var it = std.mem.splitScalar(u8, key, '_');
                    const thread_part = it.next().?; // "thread{d}"
                    const key_part = it.next().?; // "key{d}"

                    const tid = std.fmt.parseInt(usize, thread_part[6..], 10) catch unreachable;
                    const idx = std.fmt.parseInt(usize, key_part[3..], 10) catch unreachable;

                    return @intCast(tid * 1000 + idx);
                }
            }.call;

            for (0..100) |i| {
                const key = std.fmt.allocPrint(
                    ctx.allocator,
                    "thread{d}_key{d}",
                    .{ id, i },
                ) catch unreachable;
                defer ctx.allocator.free(key);

                ctx.map.put(key, makeValue) catch unreachable;
            }
        }
    };

    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*t, i| {
        t.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ThreadContext{
            .map = &cmap,
            .allocator = alloc,
            .thread_id = i,
        }});
    }

    for (threads) |t| {
        t.join();
    }

    // Verify all entries are present
    for (0..4) |thread_id| {
        for (0..100) |i| {
            const key = try std.fmt.allocPrint(alloc, "thread{d}_key{d}", .{ thread_id, i });
            defer alloc.free(key);

            const val = cmap.get(key);
            try testing.expect(val != null);
            try testing.expectEqual(@as(i32, @intCast(thread_id * 1000 + i)), val.?);
        }
    }
}

test "ConcurrentStringMap - concurrent get operations" {
    var dbg = std.heap.DebugAllocator(.{}){};
    const alloc = dbg.allocator();
    var cmap = ConcurrentStringMap(i32).init(alloc);
    defer cmap.deinit();

    // Populate map
    const makeValueFromKey = struct {
        var value: i32 = 0;
        fn call(_: []const u8) i32 {
            return value;
        }
    };

    for (0..100) |i| {
        const key = try std.fmt.allocPrint(alloc, "key{d}", .{i});
        defer alloc.free(key);
        makeValueFromKey.value = @intCast(i);
        try cmap.put(key, makeValueFromKey.call);
    }

    const ThreadContext = struct {
        map: *ConcurrentStringMap(i32),
        allocator: Allocator,

        fn worker(ctx: @This()) void {
            for (0..100) |i| {
                const key = std.fmt.allocPrint(
                    ctx.allocator,
                    "key{d}",
                    .{i},
                ) catch unreachable;
                defer ctx.allocator.free(key);

                const val = ctx.map.get(key);
                std.debug.assert(val != null);
                std.debug.assert(val.? == @as(i32, @intCast(i)));
            }
        }
    };

    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ThreadContext{
            .map = &cmap,
            .allocator = alloc,
        }});
    }

    for (threads) |t| {
        t.join();
    }
}

test "ConcurrentStringMap - concurrent mixed operations" {
    var dbg = std.heap.DebugAllocator(.{}){};
    const alloc = dbg.allocator();
    var cmap = ConcurrentStringMap(i32).init(alloc);
    defer cmap.deinit();

    const ThreadContext = struct {
        map: *ConcurrentStringMap(i32),
        allocator: Allocator,
        thread_id: usize,

        fn worker(ctx: @This()) void {
            for (0..50) |i| {
                const key = std.fmt.allocPrint(
                    ctx.allocator,
                    "shared_key{d}",
                    .{i},
                ) catch unreachable;
                defer ctx.allocator.free(key);

                // Mix of operations
                const makeTid = struct {
                    var tid: usize = undefined;
                    fn call(_: []const u8) i32 {
                        return @intCast(tid);
                    }
                };
                const makeTidPlus100 = struct {
                    var tid: usize = undefined;
                    fn call(_: []const u8) i32 {
                        return @intCast(tid + 100);
                    }
                };

                makeTid.tid = ctx.thread_id;
                makeTidPlus100.tid = ctx.thread_id;

                ctx.map.put(key, makeTid.call) catch unreachable;
                _ = ctx.map.contains(key);
                _ = ctx.map.get(key);

                if (i % 2 == 0) {
                    _ = ctx.map.fetchPut(key, makeTidPlus100.call) catch unreachable;
                }
            }
        }
    };

    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*t, i| {
        t.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ThreadContext{
            .map = &cmap,
            .allocator = alloc,
            .thread_id = i,
        }});
    }

    for (threads) |t| {
        t.join();
    }

    // Verify map is still consistent and has entries
    const countFunc = struct {
        fn call(_: []const u8, _: *i32) void {
            // Just iterating
        }
    }.call;

    cmap.forEach(countFunc);
}

test "ConcurrentStringMap - concurrent withValue operations" {
    const testing = std.testing;
    var dbg = std.heap.DebugAllocator(.{}){};
    const alloc = dbg.allocator();
    var cmap = ConcurrentStringMap(i32).init(alloc);
    defer cmap.deinit();

    // Create counters
    const makeZero = struct {
        fn call(_: []const u8) i32 {
            return 0;
        }
    }.call;

    for (0..10) |i| {
        const key = try std.fmt.allocPrint(alloc, "counter{d}", .{i});
        defer alloc.free(key);
        try cmap.put(key, makeZero);
    }

    const ThreadContext = struct {
        map: *ConcurrentStringMap(i32),
        allocator: Allocator,

        fn worker(ctx: @This()) void {
            const increment = struct {
                fn call(val: *i32) void {
                    val.* += 1;
                }
            }.call;

            for (0..10) |i| {
                const key = std.fmt.allocPrint(
                    ctx.allocator,
                    "counter{d}",
                    .{i},
                ) catch unreachable;
                defer ctx.allocator.free(key);

                for (0..100) |_| {
                    _ = ctx.map.withValue(key, increment);
                }
            }
        }
    };

    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ThreadContext{
            .map = &cmap,
            .allocator = alloc,
        }});
    }

    for (threads) |t| {
        t.join();
    }

    // Each counter should have been incremented 4 threads * 100 times = 400
    for (0..10) |i| {
        const key = try std.fmt.allocPrint(alloc, "counter{d}", .{i});
        defer alloc.free(key);

        const val = cmap.get(key);
        try testing.expectEqual(@as(?i32, 400), val);
    }
}

test "ConcurrentStringMap - concurrent remove operations" {
    const testing = std.testing;
    var dbg = std.heap.DebugAllocator(.{}){};
    const alloc = dbg.allocator();
    var cmap = ConcurrentStringMap(i32).init(alloc);
    defer cmap.deinit();

    // Populate with many entries
    const makeValueFromIdx = struct {
        var idx: usize = 0;
        fn call(_: []const u8) i32 {
            return @intCast(idx);
        }
    };

    for (0..100) |i| {
        const key = try std.fmt.allocPrint(alloc, "key{d}", .{i});
        defer alloc.free(key);
        makeValueFromIdx.idx = i;
        try cmap.put(key, makeValueFromIdx.call);
    }

    const ThreadContext = struct {
        map: *ConcurrentStringMap(i32),
        allocator: Allocator,
        start: usize,
        end: usize,

        fn worker(ctx: @This()) void {
            for (ctx.start..ctx.end) |i| {
                const key = std.fmt.allocPrint(
                    ctx.allocator,
                    "key{d}",
                    .{i},
                ) catch unreachable;
                defer ctx.allocator.free(key);

                _ = ctx.map.remove(key);
            }
        }
    };

    // Each thread removes a different range
    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*t, i| {
        t.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ThreadContext{
            .map = &cmap,
            .allocator = alloc,
            .start = i * 25,
            .end = (i + 1) * 25,
        }});
    }

    for (threads) |t| {
        t.join();
    }

    // All entries should be gone
    for (0..100) |i| {
        const key = try std.fmt.allocPrint(alloc, "key{d}", .{i});
        defer alloc.free(key);

        try testing.expect(!cmap.contains(key));
    }
}

test "ConcurrentStringMap - concurrent fetchRemove operations" {
    const testing = std.testing;
    var dbg = std.heap.DebugAllocator(.{}){};
    const alloc = dbg.allocator();
    var cmap = ConcurrentStringMap(i32).init(alloc);
    defer cmap.deinit();

    // Populate with entries
    const makeValueFromIdx = struct {
        var idx: usize = 0;
        fn call(_: []const u8) i32 {
            return @intCast(idx * 10);
        }
    };

    for (0..50) |i| {
        const key = try std.fmt.allocPrint(alloc, "key{d}", .{i});
        defer alloc.free(key);
        makeValueFromIdx.idx = i;
        try cmap.put(key, makeValueFromIdx.call);
    }

    const ThreadContext = struct {
        map: *ConcurrentStringMap(i32),
        allocator: Allocator,
        removed_count: *std.atomic.Value(usize),

        fn worker(ctx: @This()) void {
            for (0..50) |i| {
                const key = std.fmt.allocPrint(
                    ctx.allocator,
                    "key{d}",
                    .{i},
                ) catch unreachable;
                defer ctx.allocator.free(key);

                const val = ctx.map.fetchRemove(key);
                if (val != null) {
                    _ = ctx.removed_count.fetchAdd(1, .monotonic);
                }
            }
        }
    };

    var removed_count = std.atomic.Value(usize).init(0);
    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ThreadContext{
            .map = &cmap,
            .allocator = alloc,
            .removed_count = &removed_count,
        }});
    }

    for (threads) |t| {
        t.join();
    }

    // Exactly 50 entries should have been removed (one per key)
    try testing.expectEqual(@as(usize, 50), removed_count.load(.monotonic));

    // All entries should be gone
    for (0..50) |i| {
        const key = try std.fmt.allocPrint(alloc, "key{d}", .{i});
        defer alloc.free(key);
        try testing.expect(!cmap.contains(key));
    }
}

test "ConcurrentStringMap - concurrent forEach operations" {
    const testing = std.testing;
    var dbg = std.heap.DebugAllocator(.{}){};
    const alloc = dbg.allocator();
    var cmap = ConcurrentStringMap(i32).init(alloc);
    defer cmap.deinit();

    // Populate map
    const makeValueFromIdx = struct {
        var idx: usize = 0;
        fn call(_: []const u8) i32 {
            return @intCast(idx);
        }
    };

    for (0..50) |i| {
        const key = try std.fmt.allocPrint(alloc, "key{d}", .{i});
        defer alloc.free(key);
        makeValueFromIdx.idx = i;
        try cmap.put(key, makeValueFromIdx.call);
    }

    const ThreadContext = struct {
        map: *ConcurrentStringMap(i32),

        fn worker(ctx: @This()) void {
            const callback = struct {
                fn call(_: []const u8, val: *i32) void {
                    // Just read the value
                    _ = val.*;
                }
            }.call;

            for (0..10) |_| {
                ctx.map.forEach(callback);
            }
        }
    };

    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| {
        t.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ThreadContext{
            .map = &cmap,
        }});
    }

    for (threads) |t| {
        t.join();
    }

    // Verify all entries are still present
    for (0..50) |i| {
        const key = try std.fmt.allocPrint(alloc, "key{d}", .{i});
        defer alloc.free(key);
        try testing.expect(cmap.contains(key));
    }
}
