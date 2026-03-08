const std = @import("std");
const clap = @import("clap");
const Hart = @import("hart.zig").Hart;
const riscv = @import("riscv.zig");

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
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
        .{
            // positional: boot program
            .id = 'b',
            .takes_value = .one,
        },
        .{
            // positional: main program
            .id = 'p',
            .takes_value = .one,
        },
    };

    const usage_str =
        "Usage: zrv32 [-h|--help]\n" ++
        "       zrv32 <binary boot executable> <binary program executable>\n";

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

    // Program binaries will be directly stored in the emulator memory
    var hart: Hart = .{};
    try hart.init(std.heap.page_allocator);
    defer hart.deinit();

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
            'b' => {
                var fd = try std.fs.cwd().openFile(arg.value.?, .{ .mode = .read_only });
                defer fd.close();
                const buf = try allocator.alloc(u8, hart.bus.boot_rom_size);
                defer allocator.free(buf);
                var reader = fd.reader(buf);
                if (try reader.getSize() > hart.bus.boot_rom_size) {
                    try stderr.print("Boot binary \"{s}\" too large: {d} out of a maximum of {d}\n", .{arg.value.?, try reader.getSize(), hart.bus.boot_rom_size});
                    return 1;
                }
                reader.interface.readSliceAll(buf) catch |e| {
                    if (e != error.EndOfStream) return e;
                };
                hart.loadBootROMBytes(buf);
            },
            'x' => {
                var fd = try std.fs.cwd().openFile(arg.value.?, .{ .mode = .read_only });
                defer fd.close();
                const buf = try allocator.alloc(u8, hart.bus.program_rom_size);
                defer allocator.free(buf);
                var reader = fd.reader(buf);
                if (try reader.getSize() > hart.bus.program_rom_size) {
                    try stderr.print("Program binary \"{s}\" too large: {d} out of a maximum of {d}\n", .{arg.value.?, try reader.getSize(), hart.bus.program_rom_size});
                    return 1;
                }
                reader.interface.readSliceAll(buf) catch |e| {
                    if (e != error.EndOfStream) return e;
                };
                hart.loadProgramROMBytes(buf);
            },
            else => unreachable,
        }
    }

    // Free parser resources, but keep the reserved capacity
    _ = arena.reset(.free_all);

    // Command-line argument parsing done

    // Run emulator starting at boot binary until ebreak is hit
    while (!hart.ebreak) {
        hart.step();
    }

    hart.printState();

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
const expectEqual = std.testing.expectEqual;

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
    hart.loadBootROM(&.{
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
    try checkInstr(.{ .s0 = 0x12345000 }, "addi s0, s0, 1656", .{ .s0 = 0x12345678 });
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

test "slli, srli, srai" {
    try checkInstr(.{ .s0 = 7 }, "slli s1, s0, 4", .{ .s0 = 7, .s1 = 112 });
    try checkInstr(.{ .s0 = 7 }, "slli s1, s0, 30", .{ .s0 = 7, .s1 = 0xC000_0000 });
    try checkInstr(.{ .s0 = 0xC000_0000 }, "srli s1, s0, 30", .{ .s0 = 0xC000_0000, .s1 = 3 });
    try checkInstr(.{ .s0 = 0xC000_0000 }, "srai s1, s0, 30", .{ .s0 = 0xC000_0000, .s1 = 0xFFFF_FFFF });
}

test "lui, auipc" {
    // To construct a 32 bit immediate with LUI+ADDI we need to compensate for sign extension by adding 4096 to
    // the upper immediate. To construct 0x0bee_ffff, we use (0x0bee_f000 + 0x1000) and 0xfff
    try checkInstr(.{ .s0 = 4095 }, "lui s0, 200212480", .{ .s0 = 0xbef0000 });
    try checkInstr(.{ .s0 = 0xbef0000 }, "addi s0, s0, -1", .{ .s0 = 0xbeeffff });
    try checkInstr(.{ .s0 = 0 }, "auipc s0, 0", .{ .s0 = 4096 }); // boot ROM start
    try checkInstr(.{ .s0 = 0 }, "auipc s0, 4096", .{ .s0 = 8192 }); // boot ROM start + offset
}

test "add, sub" {
    try checkInstr(.{ .s0 = 0, .s1 = 100, .s2 = 23 }, "add s0, s1, s2", .{ .s0 = 123, .s1 = 100, .s2 = 23 });
    try checkInstr(.{ .s0 = 0, .s1 = 100, .s2 = 23 }, "sub s0, s1, s2", .{ .s0 = 77, .s1 = 100, .s2 = 23 });
    try checkInstr(.{ .s0 = 0, .s1 = 0x7FFF_FFFF, .s2 = 1 }, "add s0, s1, s2", .{ .s0 = 0x8000_0000, .s1 = 0x7FFF_FFFF, .s2 = 1 });
    try checkInstr(.{ .s0 = 0, .s1 = 0x8000_0000, .s2 = 1 }, "sub s0, s1, s2", .{ .s0 = 0x7FFF_FFFF, .s1 = 0x8000_0000, .s2 = 1 });
    try checkInstr(.{ .s0 = 123, .s1 = 0x8000_0001, .s2 = 0x7FFF_FFFF }, "add s0, s1, s2", .{ .s0 = 0, .s1 = 0x8000_0001, .s2 = 0x7FFF_FFFF });
}

test "slt, sltu, snez" {
    try checkInstr(.{ .s0 = 0, .s1 = 0, .s2 = 0 }, "slt s0, s1, s2", .{ .s0 = 0, .s1 = 0, .s2 = 0 });
    try checkInstr(.{ .s0 = 0, .s1 = 0, .s2 = 1 }, "slt s0, s1, s2", .{ .s0 = 1, .s1 = 0, .s2 = 1 });
    try checkInstr(.{ .s0 = 0, .s1 = @as(u32, @bitCast(@as(i32, -15))), .s2 = 1 }, "slt s0, s1, s2", .{ .s0 = 1, .s1 = @as(u32, @bitCast(@as(i32, -15))), .s2 = 1 });
    try checkInstr(.{ .s0 = 0, .s1 = 0, .s2 = 0 }, "sltu s0, s1, s2", .{ .s0 = 0, .s1 = 0, .s2 = 0 });
    try checkInstr(.{ .s0 = 0, .s1 = 0, .s2 = 1 }, "sltu s0, s1, s2", .{ .s0 = 1, .s1 = 0, .s2 = 1 });
    try checkInstr(.{ .s0 = 0, .s1 = @as(u32, @bitCast(@as(i32, -15))), .s2 = 1 }, "sltu s0, s1, s2", .{ .s0 = 0, .s1 = @as(u32, @bitCast(@as(i32, -15))), .s2 = 1 });
    try checkInstr(.{ .s0 = 0, .s1 = 0, .s2 = 0 }, "snez s0, s2", .{ .s0 = 0, .s1 = 0, .s2 = 0 });
    try checkInstr(.{ .s0 = 0, .s1 = 0, .s2 = 1 }, "snez s0, s2", .{ .s0 = 1, .s1 = 0, .s2 = 1 });
    try checkInstr(.{ .s0 = 0, .s1 = @as(u32, @bitCast(@as(i32, -15))), .s2 = 1 }, "snez s0, s1", .{ .s0 = 1, .s1 = @as(u32, @bitCast(@as(i32, -15))), .s2 = 1 });
}

test "and, or, xor" {
    try checkInstr(.{ .s0 = 0, .s1 = 7, .s2 = 10 }, "and s0, s1, s2", .{ .s0 = 2, .s1 = 7, .s2 = 10 });
    try checkInstr(.{ .s0 = 0, .s1 = 7, .s2 = 10 }, "or s0, s1, s2", .{ .s0 = 15, .s1 = 7, .s2 = 10 });
    try checkInstr(.{ .s0 = 0, .s1 = 7, .s2 = 10 }, "xor s0, s1, s2", .{ .s0 = 13, .s1 = 7, .s2 = 10 });
    try checkInstr(.{ .s0 = 0, .s1 = 7, .s2 = 0xFFFF_FFFF }, "xor s0, s1, s2", .{ .s0 = @as(u32, @bitCast(@as(i32, -8))), .s1 = 7, .s2 = 0xFFFF_FFFF });
}

test "sll, srl, sra" {
    try checkInstr(.{ .s0 = 7, .s1 = 4 }, "sll s2, s0, s1", .{ .s0 = 7, .s1 = 4, .s2 = 112 });
    try checkInstr(.{ .s0 = 7, .s1 = 30 }, "sll s2, s0, s1", .{ .s0 = 7, .s1 = 30, .s2 = 0xC000_0000 });
    try checkInstr(.{ .s0 = 0xC000_0000, .s1 = 30 }, "srl s2, s0, s1", .{ .s0 = 0xC000_0000, .s1 = 30, .s2 = 3 });
    try checkInstr(.{ .s0 = 0xC000_0000, .s1 = 30 }, "sra s2, s0, s1", .{ .s0 = 0xC000_0000, .s1 = 30, .s2 = 0xFFFF_FFFF });
}

test "jal, j" {
    // This instruction is loaded at 4096, jumps to itself, and accounting for the 2 subsequent pipeline steps,
    // pc ends up at 4096 + 8 = 4104
    try checkInstr(.{ .x1 = 0 }, "j 0", .{ .x1 = 0, .pc = 4104 });
    try checkInstr(.{ .x1 = 0 }, "jal x1, 0", .{ .x1 = 4100, .pc = 4104 });
}

test "jalr, jr, ret" {
    // Always accounting for the pipeline offset of 8 at the end
    try checkInstr(.{ .x1 = 4096 }, "jr x1, 16", .{ .x1 = 4096, .pc = 4120 });
    try checkInstr(.{ .x1 = 4096 }, "jalr x2, x1, 0", .{ .x1 = 4096, .x2 = 4100, .pc = 4104 });
    try checkInstr(.{ .x1 = 8192 - 8 }, "ret", .{ .x1 = 8192 - 8, .pc = 8192 });
}

test "beq, bne, blt, bge, bltu, bgeu, bgt, ble, bgtu, bleu" {
    // Always accounting for the pipeline offset of 8 at the end or 6 total steps with 24
    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "beq s0, s1, 100", .{ .pc = 4204 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "beq s0, s1, 100", .{ .pc = 4120 });
    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "bne s0, s1, 100", .{ .pc = 4120 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "bne s0, s1, 100", .{ .pc = 4204 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "blt s0, s1, 100", .{ .pc = 4120 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "blt s0, s1, 100", .{ .pc = 4204 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "blt s0, s1, 100", .{ .pc = 4120 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "blt s0, s1, 100", .{ .pc = 4120 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "bge s0, s1, 100", .{ .pc = 4204 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "bge s0, s1, 100", .{ .pc = 4120 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "bge s0, s1, 100", .{ .pc = 4204 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "bge s0, s1, 100", .{ .pc = 4204 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "bltu s0, s1, 100", .{ .pc = 4120 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "bltu s0, s1, 100", .{ .pc = 4204 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "bltu s0, s1, 100", .{ .pc = 4120 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "bltu s0, s1, 100", .{ .pc = 4204 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "bgeu s0, s1, 100", .{ .pc = 4204 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "bgeu s0, s1, 100", .{ .pc = 4120 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "bgeu s0, s1, 100", .{ .pc = 4204 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "bgeu s0, s1, 100", .{ .pc = 4120 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "bgt s0, s1, 100", .{ .pc = 4120 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "bgt s0, s1, 100", .{ .pc = 4120 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "bgt s0, s1, 100", .{ .pc = 4204 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "bgt s0, s1, 100", .{ .pc = 4204 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "ble s0, s1, 100", .{ .pc = 4204 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "ble s0, s1, 100", .{ .pc = 4204 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "ble s0, s1, 100", .{ .pc = 4120 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "ble s0, s1, 100", .{ .pc = 4120 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "bgtu s0, s1, 100", .{ .pc = 4120 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "bgtu s0, s1, 100", .{ .pc = 4120 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "bgtu s0, s1, 100", .{ .pc = 4204 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "bgtu s0, s1, 100", .{ .pc = 4120 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "bleu s0, s1, 100", .{ .pc = 4204 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "bleu s0, s1, 100", .{ .pc = 4204 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "bleu s0, s1, 100", .{ .pc = 4120 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "bleu s0, s1, 100", .{ .pc = 4204 });
}

test "lw, lh, lb, lhu, lbu" {
    try checkInstr(.{ .a0 = 4096 }, "lw s0, a0, 0", .{ .s0 = 0x0005_2403 }); // Loads the encoding of itself

    try checkInstr(.{ .a0 = 4096 }, "lh s0, a0, 0", .{ .s0 = 0x1403 }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 4096 }, "lh s0, a0, 2", .{ .s0 = 0x0025 }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 4099 }, "lh s0, a0, -1", .{ .s0 = 0xFFFF_FFF5 }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 4099 }, "lhu s0, a0, -1", .{ .s0 = 0xFFF5 }); // Loads the encoding of itself

    try checkInstr(.{ .a0 = 4096 }, "lb s0, a0, 0", .{ .s0 = 0x03 }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 4096 }, "lb s0, a0, 1", .{ .s0 = 0x04 }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 4096 }, "lb s0, a0, 2", .{ .s0 = 0x25 }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 4096 }, "lb s0, a0, 3", .{ .s0 = 0x00 }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 4100 }, "lb s0, a0, -1", .{ .s0 = 0xFFFF_FFFF }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 4100 }, "lbu s0, a0, -1", .{ .s0 = 0xFF }); // Loads the encoding of itself
}

test "sw, sh, sb" {
    const program = [_]u32{
        riscv.assemble("lui s0, 305418240"), // 0x12345000
        riscv.assemble("addi s0, s0, 1656"), // 0x678
        riscv.assemble("lui a0, 262144"), // ram start: 256K
        riscv.assemble("sw a0, s0, 0"),
        riscv.assemble("sh a0, s0, 4"),
        riscv.assemble("sb a0, s0, 8"),
    };

    var hart: Hart = .{};
    try hart.init(std.testing.allocator);
    defer hart.deinit();

    hart.execMany(&program);

    try expectEqual(hart.bus.get(hart.bus.ram_start, 4), 0x12345678);
    try expectEqual(hart.bus.get(hart.bus.ram_start + 4, 2), 0x5678);
    try expectEqual(hart.bus.get(hart.bus.ram_start + 8, 1), 0x78);
}
