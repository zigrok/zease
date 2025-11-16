const std = @import("std");

// =============================================================================
// .zon Serialization (Public API)
// =============================================================================

/// Prints any Zig value as a .zon-formatted string to debug output.
///
/// A convenience function for debugging that serializes values using .zon syntax.
/// Handles structs, tuples, arrays, slices, enums, unions, and primitives.
/// Uses an arena allocator internally. Unsupported types fall back to `{any}` formatting.
pub fn printZon(value: anytype) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const zon = try dumpZonAlloc(arena.allocator(), value);
    std.debug.print("{s}\n", .{zon});
}

/// Serializes any Zig value to a .zon-formatted string.
///
/// Returns an allocated string containing the .zon representation of `value`.
/// Caller owns the returned slice and must free it using the provided allocator.
///
/// Supports:
/// - Primitives: bool, int, float, void, null, undefined
/// - Collections: arrays, slices, tuples, structs
/// - Enums and tagged unions
/// - Error sets and error unions
/// - Pointers (rendered as addresses)
///
/// Arrays and slices of `u8` are rendered as string literals.
/// Unsupported types fall back to quoted `{any}` representation.
pub fn dumpZonAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
    errdefer buffer.deinit(allocator);

    try renderZon(allocator, buffer.writer(allocator), value, 0);
    return buffer.toOwnedSlice(allocator);
}

// =============================================================================
// .zon Serialization (Internal Implementation)
// =============================================================================

const indent_step: usize = 2;

/// Main .zon rendering dispatcher. Routes to specialized renderers based on type.
fn renderZon(alloc: std.mem.Allocator, writer: anytype, value: anytype, depth: usize) !void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .bool => {
            try writer.writeAll(if (value) "true" else "false");
        },
        .int, .comptime_int => {
            try writer.print("{d}", .{value});
        },
        .float, .comptime_float => {
            try std.fmt.formatFloatDecimal(value, .{}, writer);
        },
        .@"enum" => {
            try writer.print(".{s}", .{@tagName(value)});
        },
        .error_set => {
            try writer.print("error.{s}", .{@errorName(value)});
        },
        .error_union => {
            if (value) |payload| {
                try renderZon(alloc, writer, payload, depth);
            } else |err| {
                try writer.print("error.{s}", .{@errorName(err)});
            }
        },
        .optional => {
            if (value) |payload| {
                try renderZon(alloc, writer, payload, depth);
            } else {
                try writer.writeAll("null");
            }
        },
        .pointer => |ptr| {
            switch (ptr.size) {
                .one => {
                    var buf: [32]u8 = undefined;
                    const text = try std.fmt.bufPrint(&buf, "ptr(0x{x})", .{@intFromPtr(value)});
                    try writeStringLiteral(writer, text);
                },
                .slice => try renderSlice(alloc, writer, value, depth),
                .many, .c => {
                    var buf: [32]u8 = undefined;
                    const text = try std.fmt.bufPrint(&buf, "ptr[*](0x{x})", .{@intFromPtr(value)});
                    try writeStringLiteral(writer, text);
                },
            }
        },
        .array => {
            try renderArray(alloc, writer, value, depth);
        },
        .vector => {
            try renderVector(alloc, writer, value, depth);
        },
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) {
                try renderTuple(alloc, writer, value, depth);
            } else {
                try renderStruct(alloc, writer, value, depth);
            }
        },
        .@"union" => {
            try renderTaggedUnion(alloc, writer, value, depth);
        },
        .void => {
            try writer.writeAll("void");
        },
        .null => {
            try writer.writeAll("null");
        },
        .undefined => {
            try writer.writeAll("undefined");
        },
        .type => {
            try writer.print("type(.{s})", .{@typeName(value)});
        },
        else => {
            try renderFallback(alloc, writer, value);
        },
    }
}

/// Renders a struct as .zon with named fields: `.{ .field = value, ... }`
fn renderStruct(alloc: std.mem.Allocator, writer: anytype, value: anytype, depth: usize) !void {
    const info = @typeInfo(@TypeOf(value)).@"struct";
    if (info.fields.len == 0) {
        try writer.writeAll(".{}");
        return;
    }

    try writer.writeAll(".{");
    try writer.writeByte('\n');
    inline for (info.fields, 0..) |field, idx| {
        try indent(writer, depth + 1);
        try writer.print(".{s} = ", .{field.name});
        try renderZon(alloc, writer, @field(value, field.name), depth + 1);
        if (idx + 1 != info.fields.len) {
            try writer.writeAll(",");
        }
        try writer.writeByte('\n');
    }
    try indent(writer, depth);
    try writer.writeByte('}');
}

/// Renders a tuple as .zon without field names: `.{ value, ... }`
fn renderTuple(alloc: std.mem.Allocator, writer: anytype, value: anytype, depth: usize) !void {
    const info = @typeInfo(@TypeOf(value)).tuple;
    if (info.fields.len == 0) {
        try writer.writeAll(".{}");
        return;
    }

    try writer.writeAll(".{");
    try writer.writeByte('\n');
    inline for (info.fields, 0..) |field, idx| {
        try indent(writer, depth + 1);
        try renderZon(alloc, writer, @field(value, field.name), depth + 1);
        if (idx + 1 != info.fields.len) {
            try writer.writeAll(",");
        }
        try writer.writeByte('\n');
    }
    try indent(writer, depth);
    try writer.writeByte('}');
}

/// Renders an array. Treats `[N]u8` as string literals, others as item lists.
fn renderArray(alloc: std.mem.Allocator, writer: anytype, value: anytype, depth: usize) !void {
    const info = @typeInfo(@TypeOf(value)).array;
    if (info.child == u8) {
        try writeStringLiteral(writer, value[0..info.len]);
        return;
    }
    if (info.len == 0) {
        try writer.writeAll(".{}");
        return;
    }

    try writer.writeAll(".{");
    try writer.writeByte('\n');
    inline for (value, 0..) |item, idx| {
        try indent(writer, depth + 1);
        try renderZon(alloc, writer, item, depth + 1);
        if (idx + 1 != info.len) {
            try writer.writeAll(",");
        }
        try writer.writeByte('\n');
    }
    try indent(writer, depth);
    try writer.writeByte('}');
}

/// Renders a SIMD vector as a .zon list.
fn renderVector(alloc: std.mem.Allocator, writer: anytype, value: anytype, depth: usize) !void {
    const info = @typeInfo(@TypeOf(value)).vector;
    if (info.len == 0) {
        try writer.writeAll(".{}");
        return;
    }

    try writer.writeAll(".{");
    try writer.writeByte('\n');
    var i: usize = 0;
    while (i < info.len) : (i += 1) {
        try indent(writer, depth + 1);
        try renderZon(alloc, writer, value[i], depth + 1);
        if (i + 1 != info.len) {
            try writer.writeAll(",");
        }
        try writer.writeByte('\n');
    }
    try indent(writer, depth);
    try writer.writeByte('}');
}

/// Renders a slice. Treats `[]u8` and `[:0]u8` as string literals, others as item lists.
fn renderSlice(alloc: std.mem.Allocator, writer: anytype, slice: anytype, depth: usize) !void {
    const child = std.meta.Child(@TypeOf(slice));
    if (child == u8) {
        if (std.meta.sentinel(@TypeOf(slice))) |sent| {
            if (sent == 0) {
                try writeStringLiteral(writer, std.mem.sliceTo(slice, 0));
                return;
            }
        }
        try writeStringLiteral(writer, slice);
        return;
    }
    if (slice.len == 0) {
        try writer.writeAll(".{}");
        return;
    }

    try writer.writeAll(".{");
    try writer.writeByte('\n');
    var idx: usize = 0;
    while (idx < slice.len) : (idx += 1) {
        try indent(writer, depth + 1);
        try renderZon(alloc, writer, slice[idx], depth + 1);
        if (idx + 1 != slice.len) {
            try writer.writeAll(",");
        }
        try writer.writeByte('\n');
    }
    try indent(writer, depth);
    try writer.writeByte('}');
}

/// Renders a tagged union as `.tag = payload`. Untagged unions fall back to `{any}`.
fn renderTaggedUnion(alloc: std.mem.Allocator, writer: anytype, value: anytype, depth: usize) !void {
    const info = @typeInfo(@TypeOf(value));
    const union_info = info.@"union";
    if (union_info.tag_type == null) {
        try renderFallback(alloc, writer, value);
        return;
    }

    switch (value) {
        inline else => |payload, tag| {
            try writer.print(".{s} = ", .{@tagName(tag)});
            try renderZon(alloc, writer, payload, depth);
        },
    }
}

/// Fallback renderer for unsupported types. Uses `{any}` formatting wrapped in quotes.
fn renderFallback(alloc: std.mem.Allocator, writer: anytype, value: anytype) !void {
    const text = try std.fmt.allocPrint(alloc, "{any}", .{value});
    defer alloc.free(text);
    try writeStringLiteral(writer, text);
}

/// Writes indentation for the current depth level (depth * indent_step spaces).
fn indent(writer: anytype, depth: usize) !void {
    try writer.writeByteNTimes(' ', depth * indent_step);
}

/// Writes a string as a .zon string literal with proper escape sequences.
/// Handles common escapes (\n, \t, \r, \\, \") and hex escapes for control characters.
fn writeStringLiteral(writer: anytype, bytes: []const u8) !void {
    try writer.writeByte('"');
    for (bytes) |b| switch (b) {
        '\\' => try writer.writeAll("\\\\"),
        '"' => try writer.writeAll("\\\""),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        else => {
            if (b < 32 or b == 127) {
                try writer.print("\\x{x:0>2}", .{b});
            } else {
                try writer.writeByte(b);
            }
        },
    };
    try writer.writeByte('"');
}
