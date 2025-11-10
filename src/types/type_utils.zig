const std = @import("std");

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
    const target_fields_opt: ?[]const std.builtin.Type.StructField = if (std.meta.activeTag(target_info) == .@"struct")
        target_info.@"struct".fields
    else
        null;

    var issues: []const u8 = "";
    var issue_count: usize = 0;

    inline for (struct_info.fields) |field| {
        const field_type_info = @typeInfo(field.type);
        const field_tag = std.meta.activeTag(field_type_info);

        if (field_tag == .@"fn") {
            if (!@hasDecl(Target, field.name)) {
                appendIssue(&issues, &issue_count, std.fmt.comptimePrint(
                    "missing function '{s}'",
                    .{field.name},
                ));
                continue;
            }

            const expected_type = field.type;
            const actual_type = @TypeOf(@field(Target, field.name));

            if (expected_type != actual_type) {
                appendIssue(&issues, &issue_count, std.fmt.comptimePrint(
                    "function '{s}' has type {s}; expected {s}",
                    .{ field.name, @typeName(actual_type), @typeName(expected_type) },
                ));
            }
        } else {
            if (target_fields_opt) |target_fields| {
                var found = false;
                inline for (target_fields) |target_field| {
                    if (std.mem.eql(u8, target_field.name, field.name)) {
                        found = true;
                        if (target_field.type != field.type) {
                            appendIssue(&issues, &issue_count, std.fmt.comptimePrint(
                                "field '{s}' has type {s}; expected {s}",
                                .{ field.name, @typeName(target_field.type), @typeName(field.type) },
                            ));
                        }
                        break;
                    }
                }

                if (!found) {
                    appendIssue(&issues, &issue_count, std.fmt.comptimePrint(
                        "missing data field '{s}' (type {s})",
                        .{ field.name, @typeName(field.type) },
                    ));
                }
            } else {
                appendIssue(&issues, &issue_count, std.fmt.comptimePrint(
                    "requires data field '{s}' (type {s}) but target is not a struct",
                    .{ field.name, @typeName(field.type) },
                ));
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

inline fn appendIssue(issues: *[]const u8, issue_count: *usize, detail: []const u8) void {
    issues.* = if (issue_count.* == 0)
        std.fmt.comptimePrint("  • {s}", .{detail})
    else
        std.fmt.comptimePrint("{s}\n  • {s}", .{ issues.*, detail });
    issue_count.* += 1;
}
