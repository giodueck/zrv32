const std = @import("std");
const clap = @import("clap");

const Hart = @import("hart.zig").Hart;
const standardBus = @import("standardBus.zig");
const testBus = @import("testBus.zig");
const riscv = @import("riscv.zig");

const tui = @import("tui.zig");
const gui = @import("gui.zig");

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const gpa = init.gpa;

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var errbuf: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &errbuf);
    const stderr = &stderr_writer.interface;
    defer stderr.flush() catch {};

    var outbuf: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &outbuf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    // Parameters the program can take
    const params = [_]clap.Param(u8){
        .{
            .id = 'h',
            .names = .{ .short = 'h', .long = "help" },
        },
        .{
            .id = 't',
            .names = .{ .short = 't', .long = "test" },
        },
        .{
            .id = 's',
            .names = .{ .short = 's', .long = "stdout" },
        },
        .{
            .id = 'u',
            .names = .{ .short = 'u', .long = "ui" },
            .takes_value = .one,
        },
        .{
            .id = 'a',
            .names = .{ .long = "haltaddr" },
            .takes_value = .one,
        },
        .{
            // positional: boot binary, optional program binary
            .id = 'p',
            .takes_value = .many,
        },
    };

    const usage_str =
        "Usage: zrv32 [-h|--help]\n" ++
        "       zrv32 [options] <binary boot executable> [<binary program executable>]\n";

    const help_str = usage_str ++
        "\n" ++
        "This emulator implements the " ++ riscv.ISA ++ " instruction set." ++
        "\n" ++
        "\n" ++
        "<binary * executable> is an executable that contains purely Risc-V machine code.\n" ++
        "Unlike regular executable formats, like ELF, it should not contain a header.\n" ++
        "A boot binary must be provided. A program binary may be skipped.\n" ++
        "\n" ++
        "Options:\n" ++
        "       --haltaddr  When -t is also specified, sets the address at which a store\n" ++
        "                   will halt the emulator. Default value is 0x80001004 (tohost+4).\n" ++
        "   -h  --help      Print this help menu and exit.\n" ++
        "   -s  --stdout    Use basic stdout output. This mode only supports running the\n" ++
        "                   emulator until a breakpoint is hit in Machine mode.\n" ++
        "                   This is an alias of --ui=stdout.\n" ++
        "   -t  --test      Treat the boot binary executable as a test from the riscv-tests\n" ++
        "                   test suite. This loads the program at address 0x8000_0000 instead.\n" ++
        "   -u  --ui        Choose a UI. Possible values are: stdout, tui, gui. The default\n" ++
        "                   value is --ui=tui.\n" ++
        "\n";

    var iter = try init.minimal.args.iterateAllocator(arena.allocator());
    defer iter.deinit();

    // Skip program name
    _ = iter.next();

    // Initialize diagnostics
    var diag = clap.Diagnostic{};
    var parser = clap.streaming.Clap(u8, std.process.Args.Iterator){
        .params = &params,
        .iter = &iter,
        .diagnostic = &diag,
    };

    var stdout_mode = false;
    var tui_mode = true; // gui_mode = !tui_mode and !stdout_mode
    var do_test = false;
    var boot_fd: ?std.Io.File = null;
    var boot_filename: ?[]u8 = null;
    var program_fd: ?std.Io.File = null;
    var program_filename: ?[]u8 = null;
    var haltaddr: u32 = 0x8000_1004;

    // We use the streaming parser, so we consume each argument individually
    while (parser.next() catch |err| {
        // Report useful error message and exit
        try diag.report(stderr, err);

        try stderr.writeAll(usage_str);
        return 1;
    }) |arg| {
        // arg.param will point to the parameter which matched the argument
        switch (arg.param.id) {
            'h' => {
                try stderr.writeAll(help_str);
                return 0;
            },
            's' => {
                stdout_mode = true;
            },
            't' => {
                do_test = true;
            },
            'u' => {
                if (std.mem.eql(u8, arg.value.?, "stdout")) {
                    stdout_mode = true;
                    tui_mode = false;
                } else if (std.mem.eql(u8, arg.value.?, "tui")) {
                    stdout_mode = false;
                    tui_mode = true;
                } else if (std.mem.eql(u8, arg.value.?, "gui")) {
                    stdout_mode = false;
                    tui_mode = false;
                }
            },
            'a' => {
                haltaddr = try std.fmt.parseInt(u32, arg.value.?, 0);
            },
            // All positional args
            'p' => {
                if (boot_fd == null) {
                    boot_fd = try std.Io.Dir.cwd().openFile(io, arg.value.?, .{ .mode = .read_only });
                    boot_filename = try gpa.dupe(u8, arg.value.?);
                } else {
                    program_fd = try std.Io.Dir.cwd().openFile(io, arg.value.?, .{ .mode = .read_only });
                    program_filename = try gpa.dupe(u8, arg.value.?);
                }
            },
            else => unreachable,
        }
    }

    // Free parser resources
    _ = arena.reset(.free_all);

    // Command-line argument parsing done

    // Standard bus
    var bus: ?*standardBus.StandardBus = null;
    if (!do_test) bus = try gpa.create(standardBus.StandardBus);
    defer {
        if (bus != null) gpa.destroy(bus.?);
    }
    if (!do_test) try bus.?.init(gpa);
    defer {
        if (bus != null) bus.?.deinit();
    }

    var test_bus: ?*testBus.TestBus = null;
    if (do_test) test_bus = try gpa.create(testBus.TestBus);
    defer {
        if (test_bus != null) gpa.destroy(test_bus.?);
    }
    if (do_test) {
        try test_bus.?.init(gpa);
        test_bus.?.halt_address = haltaddr;
    }
    defer {
        if (test_bus != null) test_bus.?.deinit();
    }

    var hart: Hart = .{ .bus = if (!do_test) bus.?.interface() else test_bus.?.interface() };

    if (boot_fd) |fd| {
        defer {
            gpa.free(boot_filename.?);
            boot_filename = null;
            fd.close(io);
        }

        if (do_test) {
            const buf = try gpa.alloc(u8, 0x1000);
            @memset(buf, 0);
            defer gpa.free(buf);
            var reader = fd.reader(io, buf);
            if (try reader.getSize() > testBus.TestRamSize) {
                try stderr.print("Test binary \"{s}\" too large: {d} out of a maximum of {d}\n", .{ boot_filename.?, try reader.getSize(), testBus.TestRamSize });
                return 1;
            }
            const prog = try reader.interface.readAlloc(gpa, try reader.getSize());
            defer gpa.free(prog);
            hart.loadProgramBytes(testBus.TestRamStart, prog);
        } else {
            const buf = try gpa.alloc(u8, 0x1000);
            @memset(buf, 0);
            defer gpa.free(buf);
            var reader = fd.reader(io, buf);
            if (try reader.getSize() > standardBus.BootRomSize) {
                try stderr.print("Boot binary \"{s}\" too large: {d} out of a maximum of {d}\n", .{ boot_filename.?, try reader.getSize(), standardBus.BootRomSize });
                return 1;
            }
            const prog = try reader.interface.readAlloc(gpa, try reader.getSize());
            defer gpa.free(prog);
            hart.loadProgramBytes(standardBus.BootRomStart, prog);
        }
    } else {
        try stderr.print("Error: No boot binary program loaded, aborting\n", .{});
        try stderr.writeAll(usage_str);
        return 1;
    }

    if (program_fd) |fd| {
        defer {
            gpa.free(program_filename.?);
            program_filename = null;
            fd.close(io);
        }

        const buf = try gpa.alloc(u8, 0x1000);
        defer gpa.free(buf);
        var reader = fd.reader(io, buf);
        if (try reader.getSize() > standardBus.RamSize) {
            try stderr.print("Program binary \"{s}\" too large: {d} out of a maximum of {d}\n", .{ program_filename.?, try reader.getSize(), standardBus.RamSize });
            return 1;
        }
        const prog = try reader.interface.readAlloc(gpa, try reader.getSize());
        defer gpa.free(prog);
        hart.loadProgramBytes(standardBus.RamStart, prog);
    } else {
        try stderr.print("Warning: No program binary loaded\n", .{});
    }

    hart.reset();

    if (stdout_mode) {
        // Run emulator starting at boot binary until Machine mode ebreak is hit or an exception is triggered without a handler defined.
        while (!hart.ebreak and hart.fatal_exception == null) {
            hart.step();
        }

        try hart.printState(stdout);
    } else if (tui_mode) {
        try tui.tuiMain(init, &hart);
    } else {
        try gui.guiMain(init, &hart);
    }

    return 0;
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "setState" {
    var bus = testBus.TestBus{};
    try bus.init(std.testing.allocator);
    defer bus.deinit();
    var hart = Hart{ .bus = bus.interface() };

    hart.setState(.{ .zero = 15, .sp = 1234, .x31 = 31, .pc = 0x8000_0000 });
    hart.registers[1] = 1;
    hart.registers[3] = 3;
    try expect(hart.checkState(.{ .x0 = 0, .x1 = 1, .x2 = 1234, .x3 = 3, .x31 = 31, .pc = 2147483648 }));
}

test "memory access control fetch" {
    var bus = testBus.TestBus{};
    try bus.init(std.testing.allocator);
    defer bus.deinit();
    var hart = Hart{ .bus = bus.interface() };

    // RAM
    hart.loadProgram(bus.getStart(), &.{
        0b0010011, // NOP
        2,
        3,
    });

    hart.pc = bus.getStart();
    hart.flush = 3;
    hart.step();
    hart.step();
    try expect(hart.checkState(.{ .pc = bus.getStart() + 8, .fetch = 2 }));

    // Unmapped memory
    hart.pc = 0;
    hart.step();
    try expectEqual(riscv.ExceptionCause.InstructionAccessFault, hart.fatal_exception.?);

    // I/O memory
    try hart.bus.set(0x100, 1, .word);
    hart.pc = 0x100;
    hart.step();
    try expectEqual(riscv.ExceptionCause.InstructionAccessFault, hart.fatal_exception.?);
}

pub fn checkInstr(initial_state: anytype, comptime instr: []const u8, new_state: anytype) !void {
    var bus = testBus.TestBus{};
    try bus.init(std.testing.allocator);
    defer bus.deinit();
    var hart = Hart{ .bus = bus.interface() };
    hart.reset();

    hart.setState(initial_state);

    const encoded_instr = riscv.assemble(instr);
    try hart.exec(encoded_instr);

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
    try checkInstr(.{ .s0 = 4095 }, "lui s0, -266496", .{ .s0 = 0xbef00000 });
    try checkInstr(.{ .s0 = 0xbef00000 }, "addi s0, s0, -1", .{ .s0 = 0xbeefffff });
    try checkInstr(.{ .s0 = 0 }, "auipc s0, 0", .{ .s0 = 0x8000_0000 }); // boot ROM start
    try checkInstr(.{ .s0 = 0 }, "auipc s0, 1", .{ .s0 = 0x8000_1000 }); // boot ROM start + offset
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
    // This instruction is loaded at 0x8000_0000, jumps to itself, and accounting for the subsequent pipeline step,
    // pc ends up at 0x8000_0000 + 4 = 0x8000_0008
    try checkInstr(.{ .x1 = 0 }, "j 0", .{ .x1 = 0, .pc = 0x8000_0004 });
    try checkInstr(.{ .x1 = 0 }, "jal x1, 0", .{ .x1 = 0x8000_0004, .pc = 0x8000_0004 });
}

test "jalr, jr, ret" {
    // Always accounting for the pipeline offset of 4 at the end
    try checkInstr(.{ .x1 = 0x8000_0000 }, "jr x1, 16", .{ .x1 = 0x8000_0000, .pc = 0x8000_0014 });
    try checkInstr(.{ .x1 = 0x8000_0000 }, "jalr x2, x1, 0", .{ .x1 = 0x8000_0000, .x2 = 0x8000_0004, .pc = 0x8000_0004 });
    try checkInstr(.{ .x1 = 8192 - 4 }, "ret", .{ .x1 = 8192 - 4, .pc = 8192 });
}

test "beq, bne, blt, bge, bltu, bgeu, bgt, ble, bgtu, bleu" {
    // Always accounting for the pipeline offset of 4 at the end or 5 total steps with 20
    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "beq s0, s1, 100", .{ .pc = 0x8000_0068 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "beq s0, s1, 100", .{ .pc = 0x8000_0014 });
    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "bne s0, s1, 100", .{ .pc = 0x8000_0014 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "bne s0, s1, 100", .{ .pc = 0x8000_0068 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "blt s0, s1, 100", .{ .pc = 0x8000_0014 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "blt s0, s1, 100", .{ .pc = 0x8000_0068 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "blt s0, s1, 100", .{ .pc = 0x8000_0014 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "blt s0, s1, 100", .{ .pc = 0x8000_0014 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "bge s0, s1, 100", .{ .pc = 0x8000_0068 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "bge s0, s1, 100", .{ .pc = 0x8000_0014 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "bge s0, s1, 100", .{ .pc = 0x8000_0068 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "bge s0, s1, 100", .{ .pc = 0x8000_0068 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "bltu s0, s1, 100", .{ .pc = 0x8000_0014 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "bltu s0, s1, 100", .{ .pc = 0x8000_0068 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "bltu s0, s1, 100", .{ .pc = 0x8000_0014 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "bltu s0, s1, 100", .{ .pc = 0x8000_0068 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "bgeu s0, s1, 100", .{ .pc = 0x8000_0068 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "bgeu s0, s1, 100", .{ .pc = 0x8000_0014 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "bgeu s0, s1, 100", .{ .pc = 0x8000_0068 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "bgeu s0, s1, 100", .{ .pc = 0x8000_0014 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "bgt s0, s1, 100", .{ .pc = 0x8000_0014 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "bgt s0, s1, 100", .{ .pc = 0x8000_0014 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "bgt s0, s1, 100", .{ .pc = 0x8000_0068 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "bgt s0, s1, 100", .{ .pc = 0x8000_0068 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "ble s0, s1, 100", .{ .pc = 0x8000_0068 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "ble s0, s1, 100", .{ .pc = 0x8000_0068 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "ble s0, s1, 100", .{ .pc = 0x8000_0014 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "ble s0, s1, 100", .{ .pc = 0x8000_0014 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "bgtu s0, s1, 100", .{ .pc = 0x8000_0014 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "bgtu s0, s1, 100", .{ .pc = 0x8000_0014 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "bgtu s0, s1, 100", .{ .pc = 0x8000_0068 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "bgtu s0, s1, 100", .{ .pc = 0x8000_0014 });

    try checkInstr(.{ .s0 = 12, .s1 = 12 }, "bleu s0, s1, 100", .{ .pc = 0x8000_0068 });
    try checkInstr(.{ .s0 = 12, .s1 = 13 }, "bleu s0, s1, 100", .{ .pc = 0x8000_0068 });
    try checkInstr(.{ .s0 = 13, .s1 = 12 }, "bleu s0, s1, 100", .{ .pc = 0x8000_0014 });
    try checkInstr(.{ .s0 = 13, .s1 = @as(u32, @bitCast(@as(i32, -15))) }, "bleu s0, s1, 100", .{ .pc = 0x8000_0068 });
}

test "lw, lh, lb, lhu, lbu" {
    try checkInstr(.{ .a0 = 0x8000_0000 }, "lw s0, a0, 0", .{ .s0 = 0x0005_2403 }); // Loads the encoding of itself

    try checkInstr(.{ .a0 = 0x8000_0000 }, "lh s0, a0, 0", .{ .s0 = 0x1403 }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 0x8000_0000 }, "lh s0, a0, 2", .{ .s0 = 0x0025 }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 0x8000_0003 }, "lh s0, a0, -1", .{ .s0 = 0xFFFF_FFF5 }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 0x8000_0003 }, "lhu s0, a0, -1", .{ .s0 = 0xFFF5 }); // Loads the encoding of itself

    try checkInstr(.{ .a0 = 0x8000_0000 }, "lb s0, a0, 0", .{ .s0 = 0x03 }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 0x8000_0000 }, "lb s0, a0, 1", .{ .s0 = 0x04 }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 0x8000_0000 }, "lb s0, a0, 2", .{ .s0 = 0x25 }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 0x8000_0000 }, "lb s0, a0, 3", .{ .s0 = 0x00 }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 0x8000_0004 }, "lb s0, a0, -1", .{ .s0 = 0xFFFF_FFFF }); // Loads the encoding of itself
    try checkInstr(.{ .a0 = 0x8000_0004 }, "lbu s0, a0, -1", .{ .s0 = 0xFF }); // Loads the encoding of itself
}

test "sw, sh, sb" {
    const program = [_]u32{
        riscv.assemble("lui s0, 74565"), // 0x12345
        riscv.assemble("addi s0, s0, 1656"), // 0x678
        riscv.assemble("lui a0, -524288"), // ram start: 0x8000_0000
        riscv.assemble("addi a0, a0, 128"), // plus some offset
        riscv.assemble("sw a0, s0, 0"),
        riscv.assemble("sh a0, s0, 4"),
        riscv.assemble("sb a0, s0, 8"),
    };

    var bus = testBus.TestBus{};
    try bus.init(std.testing.allocator);
    defer bus.deinit();
    var hart = Hart{ .bus = bus.interface() };

    hart.execMany(&program);

    try expectEqual(0x12345678, hart.bus.get(standardBus.RamStart + 128, .word));
    try expectEqual(0x5678, hart.bus.get(standardBus.RamStart + 128 + 4, .halfword));
    try expectEqual(0x78, hart.bus.get(standardBus.RamStart + 128 + 8, .byte));
}

test "mul, mulh, mulhsu, mulhu" {
    try checkInstr(.{ .t0 = 0x123456, .t1 = 0x111555 }, "mul t2, t0, t1", .{ .t2 = 0xFE0C6E8E });
    try checkInstr(.{ .t0 = 0x123456, .t1 = 0x111555 }, "mulh t2, t0, t1", .{ .t2 = 0x136 });
    try checkInstr(.{ .t0 = 0x123456, .t1 = 0x111555 }, "mulhsu t2, t0, t1", .{ .t2 = 0x136 });
    try checkInstr(.{ .t0 = 0x123456, .t1 = 0x111555 }, "mulhu t2, t0, t1", .{ .t2 = 0x136 });

    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0x111555 }, "mul t2, t0, t1", .{ .t2 = 0xD10C6E8E });
    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0x111555 }, "mulh t2, t0, t1", .{ .t2 = 0xFFF7EE21 });
    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0x111555 }, "mulhsu t2, t0, t1", .{ .t2 = 0xFFF7EE21 });
    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0x111555 }, "mulhu t2, t0, t1", .{ .t2 = 0x90376 });

    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0x87111555 }, "mul t2, t0, t1", .{ .t2 = 0x2B0C6E8E });
    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0x87111555 }, "mulh t2, t0, t1", .{ .t2 = 0x39205365 });
    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0x87111555 }, "mulhsu t2, t0, t1", .{ .t2 = 0xC03287BB });
    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0x87111555 }, "mulhu t2, t0, t1", .{ .t2 = 0x47439D10 });
}

test "div, divu, rem, remu" {
    try checkInstr(.{ .t0 = 50400, .t1 = 25 }, "div t2, t0, t1", .{ .t2 = 2016 });
    try checkInstr(.{ .t0 = 50400, .t1 = 25 }, "divu t2, t0, t1", .{ .t2 = 2016 });
    try checkInstr(.{ .t0 = 50400, .t1 = 26 }, "rem t2, t0, t1", .{ .t2 = 12 });
    try checkInstr(.{ .t0 = 50400, .t1 = 26 }, "remu t2, t0, t1", .{ .t2 = 12 });

    try checkInstr(.{ .t0 = 0xFFFF3B20, .t1 = 25 }, "div t2, t0, t1", .{ .t2 = 0xFFFFF820 });
    try checkInstr(.{ .t0 = 0xFFFF3B20, .t1 = 25 }, "divu t2, t0, t1", .{ .t2 = 0x0A3D68C3 });
    try checkInstr(.{ .t0 = 0xFFFF3B20, .t1 = 26 }, "rem t2, t0, t1", .{ .t2 = 0xFFFFFFF4 });
    try checkInstr(.{ .t0 = 0xFFFF3B20, .t1 = 26 }, "remu t2, t0, t1", .{ .t2 = 10 });

    try checkInstr(.{ .t0 = 0xFFFF3B20, .t1 = 0xFFFFFFE7 }, "div t2, t0, t1", .{ .t2 = 2016 });
    try checkInstr(.{ .t0 = 0xFFFF3B20, .t1 = 0xFFFFFFE7 }, "divu t2, t0, t1", .{ .t2 = 0 });
    try checkInstr(.{ .t0 = 0xFFFF3B20, .t1 = 0xFFFC2F70 }, "divu t2, t0, t1", .{ .t2 = 1 });
    try checkInstr(.{ .t0 = 0xFFFF3B20, .t1 = 0xFFFFFFE6 }, "rem t2, t0, t1", .{ .t2 = 0xFFFFFFF4 });
    try checkInstr(.{ .t0 = 0xFFFF3B20, .t1 = 0xFFFFFFE6 }, "remu t2, t0, t1", .{ .t2 = 0xFFFF3B20 });

    try checkInstr(.{ .t0 = 50400, .t1 = 0xFFFFFFE7 }, "div t2, t0, t1", .{ .t2 = 0xFFFFF820 });
    try checkInstr(.{ .t0 = 50400, .t1 = 0xFFFFFFE7 }, "divu t2, t0, t1", .{ .t2 = 0 });
    try checkInstr(.{ .t0 = 50400, .t1 = 0xFFFFFFE6 }, "rem t2, t0, t1", .{ .t2 = 12 });
    try checkInstr(.{ .t0 = 50400, .t1 = 0xFFFFFFE6 }, "remu t2, t0, t1", .{ .t2 = 50400 });

    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0x87111555 }, "div t2, t0, t1", .{ .t2 = 0 });
    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0x87111555 }, "divu t2, t0, t1", .{ .t2 = 1 });
    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0x87111555 }, "rem t2, t0, t1", .{ .t2 = 0x87123456 });
    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0x87111555 }, "remu t2, t0, t1", .{ .t2 = 0x11F01 });

    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0 }, "div t2, t0, t1", .{ .t2 = 0xFFFFFFFF });
    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0 }, "divu t2, t0, t1", .{ .t2 = 0xFFFFFFFF });
    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0 }, "rem t2, t0, t1", .{ .t2 = 0x87123456 });
    try checkInstr(.{ .t0 = 0x87123456, .t1 = 0 }, "remu t2, t0, t1", .{ .t2 = 0x87123456 });

    try checkInstr(.{ .t0 = 0x80000000, .t1 = 0xFFFFFFFF }, "div t2, t0, t1", .{ .t2 = 0x80000000 });
    try checkInstr(.{ .t0 = 0x80000000, .t1 = 0xFFFFFFFF }, "divu t2, t0, t1", .{ .t2 = 0 });
    try checkInstr(.{ .t0 = 0x80000000, .t1 = 0xFFFFFFFF }, "rem t2, t0, t1", .{ .t2 = 0 });
    try checkInstr(.{ .t0 = 0x80000000, .t1 = 0xFFFFFFFF }, "remu t2, t0, t1", .{ .t2 = 0x80000000 });
}
