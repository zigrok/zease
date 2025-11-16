const std = @import("std");

/// Appends an item to a compile-time string list with customizable formatting.
/// Used internally for building contract violation messages.
inline fn appendBulletPoint(
    list: *[]const u8,
    count: *usize,
    item: []const u8,
    comptime bullet: []const u8,
    comptime separator: []const u8,
) void {
    list.* = if (count.* == 0)
        std.fmt.comptimePrint("{s}{s}", .{ bullet, item })
    else
        std.fmt.comptimePrint("{s}{s}{s}{s}", .{ list.*, separator, bullet, item });
    count.* += 1;
}

/// Checks if a target type implements the interface defined by a contract struct.
/// The contract must be a struct type describing required functions or data fields
/// and emits a single compile error that aggregates every mismatch discovered.
pub fn implementsContract(comptime Contract: type, comptime Target: type) void {
    const struct_info = switch (@typeInfo(Contract)) {
        .@"struct" => |info| info,
        else => @compileError(std.fmt.comptimePrint(
            "Contract {s} is not a struct; cannot compare with {s}",
            .{ @typeName(Contract), @typeName(Target) },
        )),
    };

    const contract_name = @typeName(Contract);
    const target_name = @typeName(Target);
    const target_info = @typeInfo(Target);
    const target_fields_opt: ?[]const std.builtin.Type.StructField = switch (target_info) {
        .@"struct" => |info| info.fields,
        else => null,
    };

    var issues: []const u8 = "";
    var issue_count: usize = 0;

    inline for (struct_info.fields) |field| {
        const field_type_info = @typeInfo(field.type);
        const field_tag = std.meta.activeTag(field_type_info);

        if (field_tag == .@"fn") {
            if (!@hasDecl(Target, field.name)) {
                appendBulletPoint(&issues, &issue_count, std.fmt.comptimePrint(
                    "missing function '{s}'",
                    .{field.name},
                ), "  • ", "\n");
                continue;
            }

            const expected_type = field.type;
            const actual_type = @TypeOf(@field(Target, field.name));

            if (expected_type != actual_type) {
                appendBulletPoint(&issues, &issue_count, std.fmt.comptimePrint(
                    "function '{s}' has type {s}; expected {s}",
                    .{ field.name, @typeName(actual_type), @typeName(expected_type) },
                ), "  • ", "\n");
            }
        } else {
            if (target_fields_opt) |target_fields| {
                var found = false;
                inline for (target_fields) |target_field| {
                    if (std.mem.eql(u8, target_field.name, field.name)) {
                        found = true;
                        if (target_field.type != field.type) {
                            appendBulletPoint(&issues, &issue_count, std.fmt.comptimePrint(
                                "field '{s}' has type {s}; expected {s}",
                                .{ field.name, @typeName(target_field.type), @typeName(field.type) },
                            ), "  • ", "\n");
                        }
                        break;
                    }
                }

                if (!found) {
                    appendBulletPoint(&issues, &issue_count, std.fmt.comptimePrint(
                        "missing data field '{s}' (type {s})",
                        .{ field.name, @typeName(field.type) },
                    ), "  • ", "\n");
                }
            } else {
                appendBulletPoint(&issues, &issue_count, std.fmt.comptimePrint(
                    "requires data field '{s}' (type {s}) but target is not a struct",
                    .{ field.name, @typeName(field.type) },
                ), "  • ", "\n");
            }
        }
    }

    if (issue_count > 0) {
        const header = std.fmt.comptimePrint(
            "[{s}] Contract violations for target {s}:",
            .{ contract_name, target_name },
        );
        @compileError(std.fmt.comptimePrint("{s}\n{s}\n", .{ header, issues }));
    }
}

// Tests
test "implementsContract - valid struct with fields and functions" {
    const Contract = struct {
        value: i32,
        name: []const u8,
        init: fn (i32) void,
        deinit: fn () void,
    };

    const ValidImpl = struct {
        value: i32,
        name: []const u8,

        pub fn init(val: i32) void {
            _ = val;
        }

        pub fn deinit() void {}
    };

    comptime {
        implementsContract(Contract, ValidImpl);
    }
}

test "implementsContract - valid struct with only functions" {
    const Contract = struct {
        create: fn () i32,
        destroy: fn (i32) void,
    };

    const ValidImpl = struct {
        pub fn create() i32 {
            return 42;
        }

        pub fn destroy(val: i32) void {
            _ = val;
        }
    };

    comptime {
        implementsContract(Contract, ValidImpl);
    }
}

test "implementsContract - valid struct with only fields" {
    const Contract = struct {
        id: u32,
        active: bool,
        data: []const u8,
    };

    const ValidImpl = struct {
        id: u32,
        active: bool,
        data: []const u8,
    };

    comptime {
        implementsContract(Contract, ValidImpl);
    }
}

test "implementsContract - empty contract" {
    const EmptyContract = struct {};

    const AnyImpl = struct {
        extra_field: i32 = 42,

        pub fn extraFunc() void {}
    };

    comptime {
        implementsContract(EmptyContract, AnyImpl);
    }
}

test "implementsContract - complex types" {
    const Contract = struct {
        allocator: std.mem.Allocator,
        list: std.ArrayList(u8),
        process: fn (std.mem.Allocator, []const u8) anyerror!void,
    };

    const ValidImpl = struct {
        allocator: std.mem.Allocator,
        list: std.ArrayList(u8),

        pub fn process(alloc: std.mem.Allocator, data: []const u8) anyerror!void {
            _ = alloc;
            _ = data;
        }
    };

    comptime {
        implementsContract(Contract, ValidImpl);
    }
}

test "implementsContract - extra members allowed" {
    const Contract = struct {
        required: i32,
        doWork: fn () void,
    };

    const ImplWithExtras = struct {
        required: i32,
        extra_field: bool = true,
        another_field: u64 = 0,

        pub fn doWork() void {}

        pub fn extraFunc() void {}
    };

    comptime {
        implementsContract(Contract, ImplWithExtras);
    }
}
