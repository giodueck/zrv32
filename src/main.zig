const std = @import("std");
const clap = @import("clap");
const Hart = @import("hart.zig").Hart;
const riscv = @import("riscv.zig");

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator{ .child_allocator = std.heap.page_allocator, .state = .{} };
    defer arena.deinit();
    const allocator = arena.allocator();

    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;

    // Parameters the program can take
    const params = [_]clap.Param(u8){
        .{
            .id = 'h',
            .names = .{ .short = 'h', .long = "help" },
        },
    };

    const usage_str =
        "Usage: zrv32 [-h|--help]\n" ++
        "       zrv32 <binary executable>\n";

    const help_str = usage_str ++ "\n" ++
        "<binary executable> is an executable that contains purely Risc-V machine code.\n" ++
        "Unlike regular executable formats, like ELF, it should not contain a header.\n\n" ++
        "Options:\n" ++
        "   -h  --help      Print this help menu and exit\n\n";

    var iter = try std.process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();

    // Skip program name
    _ = iter.next();

    // Initialize diagnostics
    var diag = clap.Diagnostic{};
    var cla_parser = clap.streaming.Clap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = &iter,
        .diagnostic = &diag,
    };

    // We use the streaming parser, so we consume each argument individually
    while (cla_parser.next() catch |err| {
        // Report useful error message and exit
        try diag.report(stderr, err);

        try stderr.writeAll(usage_str);
        try stderr.flush();
        return 1;
    }) |arg| {
        // arg.param will point to the parameter which matched the argument
        switch (arg.param.id) {
            'h' => {
                try stderr.writeAll(help_str);
                try stderr.flush();
                return 0;
            },
            else => unreachable,
        }
    }

    // Free parser resources, but keep the reserved capacity
    _ = arena.reset(.retain_capacity);

    // Command-line argument parsing done
    try stderr.print("Hello\n", .{});
    try stderr.flush();

    // API needs:
    //  - Load program
    //  - Set initial state of CPU
    //  - Run single cycle of CPU (advance each pipeline stage once)
    //  - Run single instruction (not always one cycle, runs until an instruction finishes its last stage and wasn't flushed by a branch)
    //  - By extension:
    //      - Run N cycles
    //      - Run N instructions
    //  - Run until halt (which shouldn't exist on "bare metal" but still, maybe define a set of halting conditions)
    //  - Run until breakpoint
    //
    // Testing needs:
    //  - Initialize at custom state
    //  - Interpret instructions
    //  - Run single instruction

    return 0;
}

const expect = std.testing.expect;

test "setState" {
    var hart = Hart{};

    hart.setState(.{ .zero = 15, .sp = 1234, .x31 = 31, .pc = 0x8000_0000 });
    hart.registers[1] = 1;
    hart.registers[3] = 3;
    try expect(hart.checkState(.{ .x0 = 0, .x1 = 1, .x2 = 1234, .x31 = 31, .pc = 2147483648 }));
}

test "memory access control fetch" {
    var hart = Hart{};
    try hart.init(std.testing.allocator);
    defer hart.deinit();

    // Boot ROM
    hart.loadROM(&.{
        0b0010011, // NOP
        2,
        3,
    });

    hart.setState(.{ .pc = 0x1000 });
    hart.step();
    hart.step();
    try expect(hart.checkState(.{ .pc = 0x1008, .fetch = 2 }));

    // Unmapped memory
    hart.pc = 0;
    hart.step();
    try expect(hart.checkState(.{ .pc = 4, .fetch = 0 }));

    // RAM
    hart.bus.set(0x4_0000, 1, 4);
    hart.pc = 0x4_0000;
    hart.step();
    try expect(hart.checkState(.{ .pc = 0x4_0004, .fetch = 0 }));
}

pub fn checkInstr(initial_state: anytype, comptime instr: []const u8, new_state: anytype) !void {
    var hart = Hart{};
    try hart.init(std.testing.allocator);
    defer hart.deinit();

    hart.setState(initial_state);

    const encoded_instr = riscv.assemble(instr);
    hart.exec(encoded_instr);

    try std.testing.expect(hart.checkState(new_state));
}

test "addi, mov, nop" {
    try checkInstr(.{ .x8 = 15 }, "addi x9, x8, 20", .{ .x8 = 15, .x9 = 35 });
    try checkInstr(.{ .x8 = 15 }, "addi x9, x8, -20", .{ .x8 = 15, .x9 = @as(u32, @bitCast(@as(i32, -5))) });
    try checkInstr(.{ .x8 = 15 }, "mv x10, x8", .{ .x8 = 15, .x10 = 15 });
    try checkInstr(.{ .x8 = 15 }, "nop", .{ .x8 = 15 });
}

test "slti, sltiu, seqz" {
    try checkInstr(.{ .x8 = 1, .x9 = @as(u32, @bitCast(@as(i32, -5))) }, "slti x10, x9, 2", .{ .x8 = 1, .x9 = @as(u32, @bitCast(@as(i32, -5))), .x10 = 1 });
    try checkInstr(.{ .x8 = 1, .x9 = @as(u32, @bitCast(@as(i32, -5))) }, "slti x10, x9, -4", .{ .x8 = 1, .x9 = @as(u32, @bitCast(@as(i32, -5))), .x10 = 1 });
    try checkInstr(.{ .x8 = 1, .x9 = @as(u32, @bitCast(@as(i32, -5))) }, "slti x10, x9, -6", .{ .x8 = 1, .x9 = @as(u32, @bitCast(@as(i32, -5))), .x10 = 0 });
    try checkInstr(.{ .x8 = 1, .x9 = 10 }, "sltiu x10, x8, 1", .{ .x8 = 1, .x9 = 10, .x10 = 0 });
    try checkInstr(.{ .x8 = 1, .x9 = 10 }, "sltiu x10, x8, 2", .{ .x8 = 1, .x9 = 10, .x10 = 1 });
    try checkInstr(.{ .x8 = 1, .x9 = 10 }, "seqz x10, x8", .{ .x8 = 1, .x9 = 10, .x10 = 0 });
    try checkInstr(.{ .x8 = 0, .x9 = 10 }, "seqz x10, x8", .{ .x8 = 0, .x9 = 10, .x10 = 1 });
}

test "andi, ori, xori, not" {
    try checkInstr(.{ .x4 = 7 }, "andi x5, x4, 10", .{ .x4 = 7, .x5 = 2 });
    try checkInstr(.{ .x4 = 7 }, "ori x5, x4, 10", .{ .x4 = 7, .x5 = 15 });
    try checkInstr(.{ .x4 = 7 }, "xori x5, x4, 10", .{ .x4 = 7, .x5 = 13 });
    try checkInstr(.{ .x4 = 7 }, "not x5, x4", .{ .x4 = 7, .x5 = @as(u32, @bitCast(@as(i32, -8))) });
}
