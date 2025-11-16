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
///
/// This function validates:
/// - All contract fields exist in the target with matching types
/// - All contract functions exist in the target with exact matching signatures
///
/// Example:
/// ```zig
/// const Contract = struct {
///     value: i32,
///     process: fn (i32) void,
/// };
///
/// const ValidImpl = struct {
///     value: i32,
///     pub fn process(x: i32) void { _ = x; }
/// };
///
/// comptime {
///     implementsContract(Contract, ValidImpl);
/// }
/// ```
pub fn implementsContract(comptime Contract: type, comptime Target: type) void {
    implementsContractIgnoreFuncParams(Contract, Target, true);
}

/// Checks if a target type implements the contract, with optional parameter checking.
/// When check_params is false, only verifies that functions exist and are actually functions,
/// while ignoring their parameter lists and return types. This is useful for duck-typed
/// interfaces where you want to ensure certain methods exist without enforcing exact signatures.
///
/// This function validates:
/// - All contract fields exist in the target with matching types (always strictly checked)
/// - All contract functions exist and are functions (not fields or other declarations)
/// - Function parameters and return types (only when check_params=true)
///
/// Example with check_params=false:
/// ```zig
/// const Contract = struct {
///     value: i32,
///     process: fn (i32) void,  // Contract specifies original signature
/// };
///
/// const DifferentParamsImpl = struct {
///     value: i32,
///     pub fn process(x: u64, y: bool) !void { ... }  // Different params/return, but is a function
/// };
///
/// comptime {
///     implementsContractIgnoreFuncParams(Contract, DifferentParamsImpl, false);  // Passes!
/// }
/// ```
///
/// Note: When check_params=false, the function still enforces that declared functions
/// are actually functions and not fields or other types of declarations.
pub fn implementsContractIgnoreFuncParams(comptime Contract: type, comptime Target: type, comptime check_params: bool) void {
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

            // Verify it's actually a function, not a field or other declaration
            const actual_type = @TypeOf(@field(Target, field.name));
            const actual_type_info = @typeInfo(actual_type);
            if (std.meta.activeTag(actual_type_info) != .@"fn") {
                appendBulletPoint(&issues, &issue_count, std.fmt.comptimePrint(
                    "'{s}' exists but is not a function (found type {s})",
                    .{ field.name, @typeName(actual_type) },
                ), "  • ", "\n");
                continue;
            }

            if (check_params) {
                const expected_type = field.type;

                if (expected_type != actual_type) {
                    appendBulletPoint(&issues, &issue_count, std.fmt.comptimePrint(
                        "function '{s}' has type {s}; expected {s}",
                        .{ field.name, @typeName(actual_type), @typeName(expected_type) },
                    ), "  • ", "\n");
                }
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

test "implementsContractIgnoreFuncParams - ignores function parameters and return types" {
    const Contract = struct {
        value: i32,
        process: fn (i32, []const u8) void,
        compute: fn () i32,
    };

    const DifferentSigImpl = struct {
        value: i32,

        // Different parameters and return types - should pass when ignoring params
        pub fn process(x: u64, y: bool, z: f32) !void {
            _ = x;
            _ = y;
            _ = z;
        }

        pub fn compute(data: []const u8) []const u8 {
            return data;
        }
    };

    comptime {
        implementsContractIgnoreFuncParams(Contract, DifferentSigImpl, false);
    }
}

test "implementsContractIgnoreFuncParams - validates fields strictly even when ignoring function params" {
    const Contract = struct {
        id: u32,
        name: []const u8,
        init: fn () void,
    };

    const ValidImpl = struct {
        id: u32,
        name: []const u8,

        pub fn init(allocator: std.mem.Allocator, extra: bool) !void {
            _ = allocator;
            _ = extra;
        }
    };

    comptime {
        implementsContractIgnoreFuncParams(Contract, ValidImpl, false);
    }
}

test "implementsContractIgnoreFuncParams - verifies declarations are functions not fields" {
    const Contract = struct {
        value: i32,
        process: fn () void,
    };

    const HasFunctionImpl = struct {
        value: i32,

        pub fn process(x: u64, y: bool) void {
            _ = x;
            _ = y;
        }
    };

    // Should pass - process exists as a function (not a field) even with different params
    comptime {
        implementsContractIgnoreFuncParams(Contract, HasFunctionImpl, false);
    }
}
