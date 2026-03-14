//! A Hart is to Risc-V what a Core is to x86. It is a distinct processing unit.

const std = @import("std");
const bus = @import("bus.zig");
const riscv = @import("riscv.zig");

/// Keeps the result of the last Fetch operation
const FetchBuffer = struct {
    instruction: u32 = 0,
    pc: u32 = 0,
};

/// Keeps the result of the last Decode operation
const DecodeBuffer = struct {
    instruction: u32 = 0,
    pc: u32 = 0,
    decoded: riscv.InstructionUnion = .{ .none = @as(void, undefined) },
};

/// Keeps the result of the last Read Registers operation
const ReadRegistersBuffer = struct {
    instruction: u32 = 0,
    pc: u32 = 0,
    decoded: riscv.InstructionUnion = .{ .none = @as(void, undefined) },
    op1: u32 = 0,
    op2: u32 = 0,
    rd: u5 = 0,
};

/// Keeps the result of the last Execute operation
const ExecuteBuffer = struct {
    instruction: u32 = 0,
    pc: u32 = 0,
    decoded: riscv.InstructionUnion = .{ .none = @as(void, undefined) },
    op1: u32 = 0,
    op2: u32 = 0,
    res: u32 = 0,
    addr: u32 = 0,
    rd: u5 = 0,
    fw_rd: u5 = 0,
    fw_res: u32 = 0,
    trap: ?riscv.Traps = null,
    exception: ?riscv.ExceptionCause = null,
};

// Writeback does not need to pass information to any other stage, so it doesn't get a buffer

// These CSRs must be readable but if unimplemented may always read 0
const UnimpCsr = enum {
    misa,
    mvendorid,
    marchid,
    mimpid,
    mhartid, // This is technically correct, since this is a single-threaded emulator and it must have one hart with id 0
};

pub const Hart = struct {
    // Hart state
    registers: [32]u32 = [_]u32{0} ** 32,
    pc: u32 = 0,
    next_pc: u32 = 0,
    flush: u32 = 0,
    ebreak: bool = false,
    fatal_exception: ?riscv.ExceptionCause = null,
    priv: riscv.Priv = .Machine,

    // Control and status registers
    /// Reads and writes are divided into mcycle and mcycleh
    /// cycle is a read-only shadow of this register
    mcycle: u64 = 0,
    /// Reads and writes are divided into mtime and mtimeh
    /// time is a read-only shadow of this register
    time: u64 = 0,
    /// Reads and writes are divided into minstret and minstreth
    /// instret is a read-only shadow of this register
    minstret: u64 = 0,
    /// Current Hart status
    mstatus: riscv.MStatus = std.mem.zeroes(riscv.MStatus),
    /// Current Hart status, high 32 bits
    mstatush: riscv.MStatusH = std.mem.zeroes(riscv.MStatusH),
    /// Trap vector address
    mtvec: riscv.MTrapVector = std.mem.zeroes(riscv.MTrapVector),
    /// Controls which counters are available in U-Mode. Attempts to access disabled counters trigger an illegal instruction exception
    mcounteren: u32 = 7,
    /// Scratch register for dedicated M-mode use
    mscratch: u32 = 0,
    /// Machine exception PC
    mepc: u32 = 0,
    /// Machine cause, holds the cause of a trap. If caused by an interrupt, MSBit is 1.
    mcause: u32 = 0,
    /// When a machine trap is taken, mtval is either set to exception-specific information or 0
    mtval: u32 = 0,

    // Pipeline buffers
    fetch_buf: FetchBuffer = .{},
    decode_buf: DecodeBuffer = .{},
    read_registers_buf: ReadRegistersBuffer = .{},
    execute_buf: ExecuteBuffer = .{},

    // Memory bus implementation
    bus: bus.Bus = .{},

    // Allocator for internal use
    allocator: std.mem.Allocator = undefined,

    pub fn init(self: *@This(), allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        try self.bus.init(self.allocator);
        self.reset();
    }

    pub fn deinit(self: @This()) void {
        self.bus.deinit();
    }

    pub fn reset(self: *@This()) void {
        self.fetch_buf = FetchBuffer{};
        self.decode_buf = DecodeBuffer{};
        self.read_registers_buf = ReadRegistersBuffer{};
        self.execute_buf = ExecuteBuffer{};
        self.priv = .Machine;
        self.pc = self.bus.boot_rom_start;
        self.flush = 3;
        self.mstatus = std.mem.zeroes(riscv.MStatus);
        self.mstatush = std.mem.zeroes(riscv.MStatusH);
        self.mstatush.mdt = 1;
        self.mtvec = std.mem.zeroes(riscv.MTrapVector);
        self.mcycle = 0;
        self.time = 0;
        self.minstret = 0;
        self.mcounteren = 7;
        self.mscratch = 0;
        self.mepc = 0;
        self.mcause = 0;
        self.mtval = 0;
    }

    // Testing methods

    /// Set initial state of registers and pc with an anonymous struct with the names for each register and pc
    /// as fields. Omitted fields assumed to be zero.
    pub fn setState(self: *@This(), state: anytype) void {
        inline for (@typeInfo(@TypeOf(state)).@"struct".fields) |field| {
            const value: u32 = @field(state, field.name);

            var index: u32 = 0;
            if (@hasField(@TypeOf(riscv.RegisterNames), field.name)) {
                index = @field(riscv.RegisterNames, field.name);
            } else if (@hasField(@TypeOf(riscv.RegisterAliases), field.name)) {
                index = @field(riscv.RegisterAliases, field.name);
            } else if (comptime std.mem.eql(u8, field.name, "pc")) {
                index = 32;
            } else {
                @compileError("unknown field '" ++ field.name ++ "'. 'state' must only contain fields with register names or ABI mnemonic aliases, 'pc'");
            }

            if (index < 32) {
                self.registers[index] = value;
            } else {
                self.pc = value;
            }
        }
        self.registers[0] = 0;
    }

    /// Returns true if the fields in state match the equivalent fields in the Hart. Omitted fields are not checked.
    /// In addition to the fields setState also accepts, state may have a 'fetch' field to check the content
    /// of the fetch buffer.
    pub fn checkState(self: @This(), state: anytype) bool {
        inline for (@typeInfo(@TypeOf(state)).@"struct".fields) |field| {
            const value: u32 = @field(state, field.name);

            var index: u32 = 0;
            if (@hasField(@TypeOf(riscv.RegisterNames), field.name)) {
                index = @field(riscv.RegisterNames, field.name);
            } else if (@hasField(@TypeOf(riscv.RegisterAliases), field.name)) {
                index = @field(riscv.RegisterAliases, field.name);
            } else if (comptime std.mem.eql(u8, field.name, "pc")) {
                index = 32;
            } else if (comptime std.mem.eql(u8, field.name, "fetch")) {
                index = 33;
            } else {
                @compileError("unknown field '" ++ field.name ++ "'. 'state' must only contain fields with register names or ABI mnemonic aliases, 'pc', or 'fetch'");
            }

            if (index < 32) {
                if (self.registers[index] != value) {
                    std.debug.print("Expected {d} at x{d}, got {d}\n", .{ value, index, self.registers[index] });
                    return false;
                }
            } else if (index == 32) {
                if (self.pc != value) {
                    std.debug.print("Expected {d} at pc, got {d}\n", .{ value, self.pc });
                    return false;
                }
            } else {
                if (self.fetch_buf.instruction != value) {
                    std.debug.print("Expected {d} at fetch buffer, got {d}\n", .{ value, self.fetch_buf.instruction });
                    return false;
                }
            }
        }
        return true;
    }

    /// Load a single encoded instruction, flush the pipeline, then step through until every pipeline step
    /// ran the given instruction.
    pub fn exec(self: *@This(), instr: u32) void {
        self.fetch_buf = FetchBuffer{};
        self.decode_buf = DecodeBuffer{};
        self.read_registers_buf = ReadRegistersBuffer{};
        self.execute_buf = ExecuteBuffer{};

        self.bus.set(self.bus.boot_rom_start, instr, 4);
        self.pc = self.bus.boot_rom_start;

        inline for (0..6) |_| {
            self.step();
        }
    }

    /// Load a slice of encoded instructions, flush the pipeline, then step through until every pipeline step
    /// ran the program
    pub fn execMany(self: *@This(), program: []const u32) void {
        self.fetch_buf = FetchBuffer{};
        self.decode_buf = DecodeBuffer{};
        self.read_registers_buf = ReadRegistersBuffer{};
        self.execute_buf = ExecuteBuffer{};

        self.loadBootROM(program);
        self.pc = self.bus.boot_rom_start;

        // Pipeline overhead
        inline for (0..5) |_| {
            self.step();
        }

        for (program) |_| {
            self.step();
            if (self.fatal_exception != null or self.ebreak) break;
        }
    }

    /// Loads the boot ROM. Fails silently, TODO don't
    pub fn loadBootROM(self: *@This(), rom: []const u32) void {
        for (rom, 0..) |word, i| {
            self.bus.set(self.bus.boot_rom_start + @as(u32, @intCast(i * 4)), word, 4);
        }
    }

    /// Loads the program ROM. Fails silently, TODO don't
    pub fn loadProgramROM(self: *@This(), rom: []const u32) void {
        for (rom, 0..) |word, i| {
            self.bus.set(self.bus.program_rom_start + @as(u32, @intCast(i * 4)), word, 4);
        }
    }

    /// Loads the boot ROM. Fails silently, TODO don't
    pub fn loadBootROMBytes(self: *@This(), rom: []const u8) void {
        for (rom, 0..) |byte, i| {
            self.bus.set(self.bus.boot_rom_start + @as(u32, @intCast(i)), byte, 1);
        }
    }

    /// Loads the program ROM. Fails silently, TODO don't
    pub fn loadProgramROMBytes(self: *@This(), rom: []const u8) void {
        for (rom, 0..) |byte, i| {
            self.bus.set(self.bus.program_rom_start + @as(u32, @intCast(i)), byte, 1);
        }
    }

    /// Loads the test program into test RAM. Fails silently, TODO don't
    pub fn loadTestBytes(self: *@This(), rom: []const u8) void {
        for (rom, 0..) |byte, i| {
            self.bus.set(self.bus.test_ram_start + @as(u32, @intCast(i)), byte, 1);
        }
    }


    /// Debugging method to print the current Hart state to stderr
    pub fn printState(self: @This()) void {
        std.debug.print("pc: 0x{x:0>8}\n", .{self.pc});
        const register_names = comptime a: {
            var names: [32][]const u8 = undefined;
            for (@typeInfo(@TypeOf(riscv.RegisterNames)).@"struct".fields, 0..) |f, i| {
                names[i] = f.name;
            }
            break :a names;
        };
        const register_aliases = comptime a: {
            var names: [32][]const u8 = undefined;
            for (@typeInfo(@TypeOf(riscv.RegisterAliases)).@"struct".fields, 0..) |f, i| {
                names[i] = f.name;
            }
            break :a names;
        };
        for (0..16) |i| {
            std.debug.print("{s: >4} ({s: >3}) 0x{x:08} | {s: >4} ({s: >3}) 0x{x:08}\n", .{ register_aliases[i * 2], register_names[i * 2], self.registers[i * 2], register_aliases[i * 2 + 1], register_names[i * 2 + 1], self.registers[i * 2 + 1] });
        }
        std.debug.print("\n(priv) = {d} {s}\n", .{ @intFromEnum(self.priv), @tagName(self.priv) });
        const mpp = @as(riscv.Priv, @enumFromInt(self.mstatus.mpp));
        std.debug.print("mstatus = 0x{x:08} (MPP = {d} {s})\n", .{ @as(u32, @bitCast(self.mstatus)), @intFromEnum(mpp), @tagName(mpp) });
        std.debug.print("mscratch = 0x{x:08}\n", .{self.mscratch});
        std.debug.print("mtvec = 0x{x:08}\n", .{@as(u32, @bitCast(self.mtvec))});
        std.debug.print("mepc = 0x{x:08} | mtval = 0x{x:08}\n", .{ self.mepc, self.mtval });
        std.debug.print("mcause = 0x{x:08}", .{self.mcause});
        if (self.mtval != 0) std.debug.print(" ({s})", .{@tagName(@as(riscv.ExceptionCause, @enumFromInt(self.mcause)))});
        std.debug.print("\n", .{});
        std.debug.print("cycle = 0x{x:016}\n", .{self.mcycle});
        std.debug.print("instret = 0x{x:016}\n", .{self.minstret});
        if (self.fatal_exception != null) {
            std.debug.print("\nError: Fatal unhandled exception\n", .{});
        }
    }

    /// Debugging method to print the current Hart state to an allocated string
    pub fn allocPrintState(self: @This(), allocator: std.mem.Allocator) ![]u8 {
        var lines = std.ArrayList([]u8).empty;
        defer lines.deinit(allocator);
        defer {
            for (lines.items) |line| {
                allocator.free(line);
            }
        }

        try lines.append(allocator, try std.fmt.allocPrint(allocator, "pc: 0x{x:0>8}\n", .{self.pc}));
        const register_names = comptime a: {
            var names: [32][]const u8 = undefined;
            for (@typeInfo(@TypeOf(riscv.RegisterNames)).@"struct".fields, 0..) |f, i| {
                names[i] = f.name;
            }
            break :a names;
        };
        const register_aliases = comptime a: {
            var names: [32][]const u8 = undefined;
            for (@typeInfo(@TypeOf(riscv.RegisterAliases)).@"struct".fields, 0..) |f, i| {
                names[i] = f.name;
            }
            break :a names;
        };
        for (0..16) |i| {
            try lines.append(allocator, try std.fmt.allocPrint(allocator, "{s: >4} ({s: >3}) 0x{x:08} | {s: >4} ({s: >3}) 0x{x:08}\n", .{ register_aliases[i * 2], register_names[i * 2], self.registers[i * 2], register_aliases[i * 2 + 1], register_names[i * 2 + 1], self.registers[i * 2 + 1] }));
        }
        try lines.append(allocator, try std.fmt.allocPrint(allocator, "\n(priv) = {d} {s}\n", .{ @intFromEnum(self.priv), @tagName(self.priv) }));
        const mpp = @as(riscv.Priv, @enumFromInt(self.mstatus.mpp));
        try lines.append(allocator, try std.fmt.allocPrint(allocator, "mstatus = 0x{x:08} (MPP = {d} {s})\n", .{ @as(u32, @bitCast(self.mstatus)), @intFromEnum(mpp), @tagName(mpp) }));
        try lines.append(allocator, try std.fmt.allocPrint(allocator, "mscratch = 0x{x:08}\n", .{self.mscratch}));
        try lines.append(allocator, try std.fmt.allocPrint(allocator, "mtvec = 0x{x:08}\n", .{@as(u32, @bitCast(self.mtvec))}));
        try lines.append(allocator, try std.fmt.allocPrint(allocator, "mepc = 0x{x:08} | mtval = 0x{x:08}\n", .{ self.mepc, self.mtval }));
        try lines.append(allocator, try std.fmt.allocPrint(allocator, "mcause = 0x{x:08}", .{self.mcause}));
        if (self.mtval != 0) try lines.append(allocator, try std.fmt.allocPrint(allocator, " ({s})", .{@tagName(@as(riscv.ExceptionCause, @enumFromInt(self.mcause)))}));
        try lines.append(allocator, try std.fmt.allocPrint(allocator, "\n", .{}));
        try lines.append(allocator, try std.fmt.allocPrint(allocator, "cycle = 0x{x:016}\n", .{self.mcycle}));
        try lines.append(allocator, try std.fmt.allocPrint(allocator, "instret = 0x{x:016}\n", .{self.minstret}));

        var count: usize = 0;
        for (lines.items) |line| {
            count += line.len;
        }
        const buf = try allocator.alloc(u8, count);
        var ret = std.ArrayList(u8).initBuffer(buf);
        for (lines.items) |line| {
            ret.appendSliceAssumeCapacity(line);
        }
        return buf;
    }

    // Emulation methods

    /// Sets the register rn to the value val, then sets x0 to 0.
    fn setReg(self: *@This(), rn: u5, val: u32) void {
        self.registers[rn] = val;
        self.registers[0] = 0;
    }

    /// Convenience function for branching (and not forgetting to flush!)
    fn setPc(self: *@This(), new_pc: u32) void {
        self.next_pc = new_pc;
        self.flush = 4;
    }

    /// Run a single cycle of the CPU, advancing each pipeline stage once
    pub fn step(self: *@This()) void {
        if (self.fatal_exception != null) return;

        self.next_pc = self.pc +% 4;

        // Pipeline detail: writeback needs to finish before reading registers begins.
        // Since we want to use all buffers before writing to them, we do them in reverse order anyways

        // 5. Writeback
        self.writeback(self.execute_buf);

        // 5. pt 2 Trap handling
        self.handleException(&self.execute_buf);

        // 4. Execute and Memory access
        self.execute_buf.instruction = self.read_registers_buf.instruction;
        self.execute_buf.pc = self.read_registers_buf.pc;
        self.execute_buf.decoded = self.read_registers_buf.decoded;
        self.execute_buf.op1 = self.read_registers_buf.op1;
        self.execute_buf.op2 = self.read_registers_buf.op2;
        self.execute_buf.rd = self.read_registers_buf.rd;
        self.execute_buf.trap = null;
        self.execute(&self.execute_buf);
        //  pipeline forward for next execute
        self.execute_buf.fw_res = self.execute_buf.res;
        self.execute_buf.fw_rd = self.execute_buf.rd;

        // 3. Read registers
        self.read_registers_buf.instruction = self.decode_buf.instruction;
        self.read_registers_buf.pc = self.decode_buf.pc;
        self.read_registers_buf.decoded = self.decode_buf.decoded;
        self.readRegisters(&self.read_registers_buf);

        // 2. Decode
        self.decode_buf.instruction = self.fetch_buf.instruction;
        self.decode_buf.pc = self.fetch_buf.pc;
        const decode_r: riscv.RTypeInstruction = @bitCast(self.decode_buf.instruction);
        const decode_ins_type = riscv.Opcode.getType(@enumFromInt(decode_r.opcode));
        switch (decode_ins_type) {
            .R => self.decode_buf.decoded = .{ .R = @bitCast(self.decode_buf.instruction) },
            .I => self.decode_buf.decoded = .{ .I = @bitCast(self.decode_buf.instruction) },
            .S => self.decode_buf.decoded = .{ .S = @bitCast(self.decode_buf.instruction) },
            .B => self.decode_buf.decoded = .{ .B = @bitCast(self.decode_buf.instruction) },
            .U => self.decode_buf.decoded = .{ .U = @bitCast(self.decode_buf.instruction) },
            .J => self.decode_buf.decoded = .{ .J = @bitCast(self.decode_buf.instruction) },
            else => self.decode_buf.decoded = .{ .none = @as(void, undefined) },
        }

        // 1. Fetch
        self.fetch_buf.instruction = self.bus.fetch(self.pc) catch |e| err: {
            if (e == bus.MemoryError.InstructionAddressMisaligned) {
                self.execute_buf.exception = riscv.ExceptionCause.InstructionAddressMisaligned;
            } else if (e == bus.MemoryError.InstructionAccessFault) {
                self.execute_buf.exception = riscv.ExceptionCause.InstructionAccessFault;
            }
            self.fatal_exception = self.execute_buf.exception.?;
            break :err 0;
        };
        self.fetch_buf.pc = self.pc;

        self.flush -|= 1;
        self.pc = self.next_pc;
        self.updateCounters(self.execute_buf);
    }

    /// Reads the needed registers into the Read Registers step buffer.
    fn readRegisters(self: *@This(), buf: *ReadRegistersBuffer) void {
        buf.op1 = 0;
        buf.op2 = 0;
        switch (buf.decoded) {
            .R => |value| {
                buf.op1 = self.registers[value.rs1];
                buf.op2 = self.registers[value.rs2];
                buf.rd = buf.decoded.R.rd;
            },
            .I => |value| {
                buf.op1 = self.registers[value.rs1];
                buf.rd = buf.decoded.I.rd;
            },
            .S => |value| {
                buf.op1 = self.registers[value.rs1];
                buf.op2 = self.registers[value.rs2];
                buf.rd = 0;
            },
            .B => |value| {
                buf.op1 = self.registers[value.rs1];
                buf.op2 = self.registers[value.rs2];
                buf.rd = 0;
            },
            .U => {
                buf.rd = buf.decoded.U.rd;
            },
            .J => {
                buf.rd = buf.decoded.J.rd;
            },
            else => {},
        }
    }

    /// Handle exceptions set by the Hart
    fn handleException(self: *@This(), buf: *ExecuteBuffer) void {
        if (buf.exception == null) return;
        // Breakpoints in machine mode stop the emulator
        if (buf.exception.? == .Breakpoint and self.priv == .Machine) {
            self.ebreak = true;
            return;
        }
        // If no trap vector was set, all exceptions halt execution
        if (self.mtvec.base == 0) self.fatal_exception = buf.exception.?;

        self.mepc = buf.pc;
        self.mtval = buf.instruction;
        self.mstatus.mpp = @intFromEnum(self.priv);
        self.priv = .Machine;
        self.mcause = @intFromEnum(buf.exception.?);
        self.setPc(@as(u32, @bitCast(self.mtvec)) & 0xFFFF_FFFC);
        // Exception handled
        buf.exception = null;
    }

    /// Executes the instruction
    fn execute(self: *@This(), buf: *ExecuteBuffer) void {
        // After a branch or jump, the pipeline must be flushed, which invalidates instructions in the pipeline
        // that were not meant to be executed.
        if (self.flush > 0) {
            buf.instruction = 0;
            buf.res = 0;
            buf.rd = 0;
            return;
        }

        // Pipeline forward
        if (buf.fw_rd != 0) {
            switch (buf.decoded) {
                .R => {
                    if (buf.decoded.R.rs1 == buf.fw_rd) buf.op1 = buf.fw_res;
                    if (buf.decoded.R.rs2 == buf.fw_rd) buf.op2 = buf.fw_res;
                },
                .I => {
                    if (buf.decoded.I.rs1 == buf.fw_rd) buf.op1 = buf.fw_res;
                },
                .S => {
                    if (buf.decoded.S.rs1 == buf.fw_rd) buf.op1 = buf.fw_res;
                    if (buf.decoded.S.rs2 == buf.fw_rd) buf.op2 = buf.fw_res;
                },
                .B => {
                    if (buf.decoded.B.rs1 == buf.fw_rd) buf.op1 = buf.fw_res;
                    if (buf.decoded.B.rs2 == buf.fw_rd) buf.op2 = buf.fw_res;
                },
                .J, .U, .none => {},
            }
        }

        buf.res = 0;
        // TODO finish
        switch (buf.decoded) {
            .R => |value| {
                switch (value.opcode) {
                    @intFromEnum(riscv.Opcode.OP) => {
                        executeOp(self, buf);
                    },
                    else => {
                        buf.exception = .IllegalInstruction;
                    },
                }
            },
            .I => |value| {
                switch (value.opcode) {
                    @intFromEnum(riscv.Opcode.LOAD) => {
                        executeMemoryAccess(self, buf);
                    },
                    @intFromEnum(riscv.Opcode.MISC_MEM) => {
                        // Memory access is entirely sequential and we only have one core anyways,
                        // so FENCE will be a NOP.
                        // PAUSE is also a NOP.
                    },
                    @intFromEnum(riscv.Opcode.OP_IMM) => {
                        executeOpImm(self, buf);
                    },
                    @intFromEnum(riscv.Opcode.JALR) => {
                        executeJalr(self, buf);
                    },
                    @intFromEnum(riscv.Opcode.SYSTEM) => {
                        executeSystem(self, buf);
                    },
                    else => {
                        buf.exception = .IllegalInstruction;
                    },
                }
            },
            .S => |value| {
                switch (value.opcode) {
                    @intFromEnum(riscv.Opcode.STORE) => {
                        executeMemoryAccess(self, buf);
                    },
                    else => {
                        buf.exception = .IllegalInstruction;
                    },
                }
            },
            .B => |value| {
                switch (value.opcode) {
                    @intFromEnum(riscv.Opcode.BRANCH) => {
                        executeBranch(self, buf);
                    },
                    else => {
                        buf.exception = .IllegalInstruction;
                    },
                }
            },
            .U => |value| {
                switch (value.opcode) {
                    @intFromEnum(riscv.Opcode.LUI) => {
                        executeLui(self, buf);
                    },
                    @intFromEnum(riscv.Opcode.AUIPC) => {
                        executeAuipc(self, buf);
                    },
                    else => {
                        buf.exception = .IllegalInstruction;
                    },
                }
            },
            .J => |value| {
                switch (value.opcode) {
                    @intFromEnum(riscv.Opcode.JAL) => {
                        executeJal(self, buf);
                    },
                    else => {
                        buf.exception = .IllegalInstruction;
                    },
                }
            },
            .none => {
                buf.exception = .IllegalInstruction;
            },
        }
    }

    fn executeOpImm(self: *@This(), buf: *ExecuteBuffer) void {
        _ = self;
        const decoded: riscv.ITypeInstruction = @bitCast(buf.instruction);
        switch (decoded.funct3) {
            riscv.Funct3.OP_IMM.addi => {
                buf.res = buf.op1 +% riscv.getIImmediate(buf.instruction);
            },
            riscv.Funct3.OP_IMM.slti => {
                const rs1: i32 = @bitCast(buf.op1);
                const imm: i32 = @bitCast(riscv.getIImmediate(buf.instruction));
                buf.res = if (rs1 < imm) 1 else 0;
            },
            riscv.Funct3.OP_IMM.sltiu => {
                const rs1 = buf.op1;
                const imm = riscv.getIImmediate(buf.instruction);
                buf.res = if (rs1 < imm) 1 else 0;
            },
            riscv.Funct3.OP_IMM.andi => {
                buf.res = buf.op1 & riscv.getIImmediate(buf.instruction);
            },
            riscv.Funct3.OP_IMM.ori => {
                buf.res = buf.op1 | riscv.getIImmediate(buf.instruction);
            },
            riscv.Funct3.OP_IMM.xori => {
                buf.res = buf.op1 ^ riscv.getIImmediate(buf.instruction);
            },
            riscv.Funct3.OP_IMM.slli => {
                buf.res = std.math.shl(u32, buf.op1, decoded.imm & 0x1F);
            },
            riscv.Funct3.OP_IMM.srli => {
                if (decoded.imm >> 5 == 0b0100000) {
                    // arithmetic
                    buf.res = std.math.shr(u32, buf.op1, decoded.imm & 0x1F);
                    if (buf.op1 >> 31 == 1) {
                        buf.res |= std.math.shl(u32, 0xFFFF_FFFF, 32 - (decoded.imm & 0x1F));
                    }
                } else if (decoded.imm >> 5 == 0) {
                    // logical
                    buf.res = std.math.shr(u32, buf.op1, decoded.imm & 0x1F);
                } else {
                    buf.exception = .IllegalInstruction;
                }
            },
        }
    }

    fn executeLui(self: *@This(), buf: *ExecuteBuffer) void {
        _ = self;
        buf.res = riscv.getUImmediate(buf.instruction);
    }

    fn executeAuipc(self: *@This(), buf: *ExecuteBuffer) void {
        // This accounts for pipeline steps, so the PC gotten is the address of this exact instruction
        buf.res = self.pc -% 12 +% riscv.getUImmediate(buf.instruction);
    }

    fn executeOp(self: *@This(), buf: *ExecuteBuffer) void {
        _ = self;
        const decoded: riscv.RTypeInstruction = @bitCast(buf.instruction);
        switch (decoded.funct3) {
            riscv.Funct3.OP.add => {
                buf.res = buf.op1;
                if (decoded.funct7 == 0) { // add
                    buf.res +%= buf.op2;
                } else if (decoded.funct7 == 0b0100000) { // sub
                    buf.res -%= buf.op2;
                } else {
                    buf.exception = .IllegalInstruction;
                }
            },
            riscv.Funct3.OP.slt => {
                const rs1: i32 = @bitCast(buf.op1);
                const rs2: i32 = @bitCast(buf.op2);
                buf.res = if (rs1 < rs2) 1 else 0;
            },
            riscv.Funct3.OP.sltu => {
                const rs1 = buf.op1;
                const rs2 = buf.op2;
                buf.res = if (rs1 < rs2) 1 else 0;
            },
            riscv.Funct3.OP.@"and" => {
                buf.res = buf.op1 & buf.op2;
            },
            riscv.Funct3.OP.@"or" => {
                buf.res = buf.op1 | buf.op2;
            },
            riscv.Funct3.OP.xor => {
                buf.res = buf.op1 ^ buf.op2;
            },
            riscv.Funct3.OP.sll => {
                buf.res = std.math.shl(u32, buf.op1, buf.op2 & 0x1F);
            },
            riscv.Funct3.OP.srl => {
                if (decoded.funct7 == 0b0100000) {
                    // arithmetic
                    buf.res = std.math.shr(u32, buf.op1, buf.op2 & 0x1F);
                    if (buf.op1 >> 31 == 1) {
                        buf.res |= std.math.shl(u32, 0xFFFF_FFFF, 32 - (buf.op2 & 0x1F));
                    }
                } else if (decoded.funct7 == 0) {
                    // logical
                    buf.res = std.math.shr(u32, buf.op1, buf.op2 & 0x1F);
                } else {
                    buf.exception = .IllegalInstruction;
                }
            },
        }
    }

    fn executeJal(self: *@This(), buf: *ExecuteBuffer) void {
        buf.res = buf.pc +% 4;
        self.setPc(buf.pc +% riscv.getJImmediate(buf.instruction));
    }

    fn executeJalr(self: *@This(), buf: *ExecuteBuffer) void {
        buf.res = buf.pc +% 4;
        self.setPc(riscv.getIImmediate(buf.instruction) +% buf.op1);
    }

    fn executeBranch(self: *@This(), buf: *ExecuteBuffer) void {
        const dest = buf.pc +% riscv.getBImmediate(buf.instruction);
        switch (buf.decoded.B.funct3) {
            riscv.Funct3.BRANCH.beq => {
                if (buf.op1 == buf.op2) {
                    self.setPc(dest);
                }
            },
            riscv.Funct3.BRANCH.bne => {
                if (buf.op1 != buf.op2) {
                    self.setPc(dest);
                }
            },
            riscv.Funct3.BRANCH.blt => {
                const rs1: i32 = @bitCast(buf.op1);
                const rs2: i32 = @bitCast(buf.op2);
                if (rs1 < rs2) {
                    self.setPc(dest);
                }
            },
            riscv.Funct3.BRANCH.bge => {
                const rs1: i32 = @bitCast(buf.op1);
                const rs2: i32 = @bitCast(buf.op2);
                if (rs1 >= rs2) {
                    self.setPc(dest);
                }
            },
            riscv.Funct3.BRANCH.bltu => {
                if (buf.op1 < buf.op2) {
                    self.setPc(dest);
                }
            },
            riscv.Funct3.BRANCH.bgeu => {
                if (buf.op1 >= buf.op2) {
                    self.setPc(dest);
                }
            },
            else => {
                buf.exception = .IllegalInstruction;
            },
        }
    }

    /// Executes memory access operations like LOAD and STORE
    fn executeMemoryAccess(self: *@This(), buf: *ExecuteBuffer) void {
        const decoded: riscv.ITypeInstruction = @bitCast(buf.instruction);
        if (decoded.opcode == @intFromEnum(riscv.Opcode.LOAD)) {
            buf.addr = buf.op1 +% riscv.getIImmediate(buf.instruction);
            switch (buf.decoded.I.funct3) {
                riscv.Funct3.LOAD.lb, riscv.Funct3.LOAD.lbu => |value| {
                    buf.res = self.bus.load(buf.addr, 1) catch |e| err: {
                        if (e == bus.MemoryError.LoadAccessFault) {
                            buf.trap = riscv.Traps.LoadAccessFault;
                        } else if (e == bus.MemoryError.IllegalInstruction) {
                            buf.exception = .IllegalInstruction;
                        }
                        break :err 0;
                    };
                    if (value & 4 == 0 and buf.res >> 7 == 1) {
                        buf.res |= 0xFFFF_FF00;
                    }
                },
                riscv.Funct3.LOAD.lh, riscv.Funct3.LOAD.lhu => |value| {
                    buf.res = self.bus.load(buf.addr, 2) catch |e| err: {
                        if (e == bus.MemoryError.LoadAccessFault) {
                            buf.trap = riscv.Traps.LoadAccessFault;
                        } else if (e == bus.MemoryError.IllegalInstruction) {
                            buf.exception = .IllegalInstruction;
                        }
                        break :err 0;
                    };
                    if (value & 4 == 0 and buf.res >> 15 == 1) {
                        buf.res |= 0xFFFF_0000;
                    }
                },
                riscv.Funct3.LOAD.lw => {
                    buf.res = self.bus.load(buf.addr, 4) catch |e| err: {
                        if (e == bus.MemoryError.LoadAccessFault) {
                            buf.trap = riscv.Traps.LoadAccessFault;
                        } else if (e == bus.MemoryError.IllegalInstruction) {
                            buf.exception = .IllegalInstruction;
                        }
                        break :err 0;
                    };
                },
                else => {
                    buf.exception = .IllegalInstruction;
                },
            }
        } else if (decoded.opcode == @intFromEnum(riscv.Opcode.STORE)) {
            buf.addr = buf.op1 +% riscv.getSImmediate(buf.instruction);
            switch (buf.decoded.S.funct3) {
                riscv.Funct3.STORE.sb => {
                    self.bus.store(buf.addr, buf.op2, 1) catch |e| {
                        if (e == bus.MemoryError.StoreAccessFault) {
                            buf.trap = riscv.Traps.StoreAccessFault;
                        } else if (e == bus.MemoryError.IllegalInstruction) {
                            buf.exception = .IllegalInstruction;
                        }
                    };
                },
                riscv.Funct3.STORE.sh => {
                    self.bus.store(buf.addr, buf.op2, 2) catch |e| {
                        if (e == bus.MemoryError.StoreAccessFault) {
                            buf.trap = riscv.Traps.StoreAccessFault;
                        } else if (e == bus.MemoryError.IllegalInstruction) {
                            buf.exception = .IllegalInstruction;
                        }
                    };
                },
                riscv.Funct3.STORE.sw => {
                    self.bus.store(buf.addr, buf.op2, 4) catch |e| {
                        if (e == bus.MemoryError.StoreAccessFault) {
                            buf.trap = riscv.Traps.StoreAccessFault;
                        } else if (e == bus.MemoryError.IllegalInstruction) {
                            buf.exception = .IllegalInstruction;
                        }
                    };
                },
                else => {
                    buf.exception = .IllegalInstruction;
                },
            }
        }
    }

    fn executeSystem(self: *@This(), buf: *ExecuteBuffer) void {
        const decoded = buf.decoded.I;
        switch (decoded.funct3) {
            riscv.Funct3.SYSTEM.priv => {
                switch (decoded.imm) {
                    riscv.PrivImmediates.ecall => {
                        buf.exception = if (self.priv == .Machine) .EnvironmentCallMMode else .EnvironmentCallUMode;
                    },
                    riscv.PrivImmediates.ebreak => {
                        buf.exception = .Breakpoint;
                    },
                    riscv.PrivImmediates.mret => {
                        if (self.priv != .Machine) {
                            buf.exception = .IllegalInstruction;
                        } else {
                            self.priv = @enumFromInt(self.mstatus.mpp);
                            self.mstatus.mie = self.mstatus.mpie;
                            self.mstatus.mpie = 1;
                            self.mstatus.mpp = @intFromEnum(riscv.Priv.User);
                            self.mstatus.verify();
                            self.setPc(self.mepc);
                        }
                    },
                    riscv.PrivImmediates.wfi => {
                        // A legal implementation is to implement this as NOP
                    },
                    else => {
                        buf.exception = .IllegalInstruction;
                    },
                }
            },
            riscv.Funct3.SYSTEM.csrrw => {
                if (buf.rd != 0) buf.res = self.readCsr(@bitCast(decoded.imm)) catch a: {
                    buf.exception = .IllegalInstruction;
                    break :a 0;
                };
                self.writeCsr(@bitCast(decoded.imm), buf.op1, .write) catch {
                    buf.exception = .IllegalInstruction;
                };
            },
            riscv.Funct3.SYSTEM.csrrs => {
                buf.res = self.readCsr(@bitCast(decoded.imm)) catch a: {
                    buf.exception = .IllegalInstruction;
                    break :a 0;
                };
                if (decoded.rs1 != 0) self.writeCsr(@bitCast(decoded.imm), buf.op1, .set) catch {
                    buf.exception = .IllegalInstruction;
                };
            },
            riscv.Funct3.SYSTEM.csrrc => {
                buf.res = self.readCsr(@bitCast(decoded.imm)) catch a: {
                    buf.exception = .IllegalInstruction;
                    break :a 0;
                };
                if (decoded.rs1 != 0) self.writeCsr(@bitCast(decoded.imm), buf.op1, .clear) catch {
                    buf.exception = .IllegalInstruction;
                };
            },
            riscv.Funct3.SYSTEM.csrrwi => {
                if (buf.rd != 0) buf.res = self.readCsr(@bitCast(decoded.imm)) catch a: {
                    buf.exception = .IllegalInstruction;
                    break :a 0;
                };
                self.writeCsr(@bitCast(decoded.imm), decoded.rs1, .write) catch {
                    buf.exception = .IllegalInstruction;
                };
            },
            riscv.Funct3.SYSTEM.csrrsi => {
                buf.res = self.readCsr(@bitCast(decoded.imm)) catch a: {
                    buf.exception = .IllegalInstruction;
                    break :a 0;
                };
                if (decoded.rs1 != 0) self.writeCsr(@bitCast(decoded.imm), decoded.rs1, .set) catch {
                    buf.exception = .IllegalInstruction;
                };
            },
            riscv.Funct3.SYSTEM.csrrci => {
                buf.res = self.readCsr(@bitCast(decoded.imm)) catch a: {
                    buf.exception = .IllegalInstruction;
                    break :a 0;
                };
                if (decoded.rs1 != 0) self.writeCsr(@bitCast(decoded.imm), decoded.rs1, .clear) catch {
                    buf.exception = .IllegalInstruction;
                };
            },
            else => {
                buf.exception = .IllegalInstruction;
            },
        }
    }

    /// Returns the value of the CSR at the address. If access is forbidden or the CSR does not exist, errors with illegal instruction
    fn readCsr(self: @This(), addr: u12) riscv.Exception!u32 {
        switch (@as(riscv.CsrNumber, @enumFromInt(addr))) {
            _ => {
                return riscv.Exception.IllegalInstruction;
            },
            else => |number| {
                const priv: riscv.CsrPriv = riscv.CsrPrivs.get(number).?;
                if (@intFromEnum(self.priv) < @intFromEnum(priv.priv)) {
                    return riscv.Exception.IllegalInstruction;
                } else if (priv.zero) {
                    return 0;
                }

                switch (number) {
                    .cycle, .mcycle => {
                        return @truncate(self.mcycle);
                    },
                    .cycleh, .mcycleh => {
                        return @truncate(self.mcycle >> 32);
                    },
                    .time => {
                        return @truncate(self.time);
                    },
                    .timeh => {
                        return @truncate(self.time >> 32);
                    },
                    .instret, .minstret => {
                        return @truncate(self.minstret);
                    },
                    .instreth, .minstreth => {
                        return @truncate(self.minstret >> 32);
                    },
                    .mstatus => {
                        return @bitCast(self.mstatus);
                    },
                    .mstatush => {
                        return @bitCast(self.mstatush);
                    },
                    .mtvec => {
                        return @bitCast(self.mtvec);
                    },
                    .mcounteren => {
                        return self.mcounteren;
                    },
                    .mscratch => {
                        return self.mscratch;
                    },
                    .mepc => {
                        return self.mepc;
                    },
                    .mcause => {
                        return self.mcause;
                    },
                    .mtval => {
                        return self.mtval;
                    },
                    else => unreachable,
                }
            },
        }
    }

    /// Sets the value of the CSR at the address. If access is forbidden or the CSR does not exist, errors with illegal instruction
    fn writeCsr(self: *@This(), addr: u12, value: u32, op: enum { write, set, clear }) riscv.Exception!void {
        switch (@as(riscv.CsrNumber, @enumFromInt(addr))) {
            _ => {
                return riscv.Exception.IllegalInstruction;
            },
            else => |number| {
                const priv: riscv.CsrPriv = riscv.CsrPrivs.get(number).?;
                if (@intFromEnum(self.priv) < @intFromEnum(priv.priv) or !priv.write) {
                    return riscv.Exception.IllegalInstruction;
                } else if (priv.zero) {
                    return;
                }

                switch (number) {
                    .mcycle => {
                        if (op == .write) {
                            self.mcycle &= 0xFFFF_FFFF_0000_0000;
                            self.mcycle |= value;
                        } else if (op == .set) {
                            self.mcycle |= value;
                        } else {
                            self.mcycle &= ~value;
                        }
                    },
                    .mcycleh => {
                        if (op == .write) {
                            self.mcycle &= 0xFFFF_FFFF;
                            self.mcycle |= @as(u64, value) << 32;
                        } else if (op == .set) {
                            self.mcycle |= @as(u64, value) << 32;
                        } else {
                            self.mcycle &= ~@as(u64, value) << 32;
                        }
                    },
                    .time => {
                        if (op == .write) {
                            self.time &= 0xFFFF_FFFF_0000_0000;
                            self.time |= value;
                        } else if (op == .set) {
                            self.time |= value;
                        } else {
                            self.time &= ~value;
                        }
                    },
                    .timeh => {
                        if (op == .write) {
                            self.time &= 0xFFFF_FFFF;
                            self.time |= @as(u64, value) << 32;
                        } else if (op == .set) {
                            self.time |= @as(u64, value) << 32;
                        } else {
                            self.time &= ~@as(u64, value) << 32;
                        }
                    },
                    .minstret => {
                        if (op == .write) {
                            self.minstret &= 0xFFFF_FFFF_0000_0000;
                            self.minstret |= value;
                        } else if (op == .set) {
                            self.minstret |= value;
                        } else {
                            self.minstret &= ~value;
                        }
                    },
                    .minstreth => {
                        if (op == .write) {
                            self.minstret &= 0xFFFF_FFFF;
                            self.minstret |= @as(u64, value) << 32;
                        } else if (op == .set) {
                            self.minstret |= @as(u64, value) << 32;
                        } else {
                            self.minstret &= ~@as(u64, value) << 32;
                        }
                    },
                    .mstatus => {
                        if (op == .write) {
                            self.mstatus = @bitCast(value);
                        } else if (op == .set) {
                            self.mstatus = @bitCast(@as(u32, @bitCast(self.mstatus)) | value);
                        } else {
                            self.mstatus = @bitCast(@as(u32, @bitCast(self.mstatus)) & ~value);
                        }
                        self.mstatus.verify();
                    },
                    .mstatush => {
                        if (op == .write) {
                            self.mstatush = @bitCast(value);
                        } else if (op == .set) {
                            self.mstatush = @bitCast(@as(u32, @bitCast(self.mstatush)) | value);
                        } else {
                            self.mstatush = @bitCast(@as(u32, @bitCast(self.mstatush)) & ~value);
                        }
                        self.mstatush.verify();
                    },
                    .mtvec => {
                        if (op == .write) {
                            self.mtvec = @bitCast(value);
                        } else if (op == .set) {
                            self.mtvec = @bitCast(@as(u32, @bitCast(self.mtvec)) | value);
                        } else {
                            self.mtvec = @bitCast(@as(u32, @bitCast(self.mtvec)) & ~value);
                        }
                        self.mtvec.verify();
                    },
                    .mcounteren => {
                        if (op == .write) {
                            self.mcounteren = @bitCast(value);
                        } else if (op == .set) {
                            self.mcounteren |= @bitCast(value);
                        } else {
                            self.mcounteren &= ~@as(u32, @bitCast(value));
                        }
                    },
                    .mscratch => {
                        if (op == .write) {
                            self.mscratch = @bitCast(value);
                        } else if (op == .set) {
                            self.mscratch |= @bitCast(value);
                        } else {
                            self.mscratch &= ~@as(u32, @bitCast(value));
                        }
                    },
                    .mepc => {
                        if (op == .write) {
                            self.mepc = @bitCast(value);
                        } else if (op == .set) {
                            self.mepc |= @bitCast(value);
                        } else {
                            self.mepc &= ~@as(u32, @bitCast(value));
                        }
                    },
                    .mcause => {
                        if (op == .write) {
                            self.mcause = @bitCast(value);
                        } else if (op == .set) {
                            self.mcause |= @bitCast(value);
                        } else {
                            self.mcause &= ~@as(u32, @bitCast(value));
                        }
                    },
                    .mtval => {
                        if (op == .write) {
                            self.mtval = @bitCast(value);
                        } else if (op == .set) {
                            self.mtval |= @bitCast(value);
                        } else {
                            self.mtval &= ~@as(u32, @bitCast(value));
                        }
                    },
                    else => unreachable,
                }
            },
        }
    }

    /// Writes pipeline results to the register file
    fn writeback(self: *@This(), buf: ExecuteBuffer) void {
        var rd: u5 = 0;
        if (buf.instruction == 0) return;
        switch (buf.decoded) {
            .R => |value| {
                rd = value.rd;
            },
            .I => |value| {
                rd = value.rd;
            },
            .U => |value| {
                rd = value.rd;
            },
            .J => |value| {
                rd = value.rd;
            },
            else => {},
        }
        // setReg discards x0 itself
        self.setReg(rd, buf.res);
    }

    /// Updates performance and time counters
    fn updateCounters(self: *@This(), buf: ExecuteBuffer) void {
        if (self.mcounteren & 1 > 0) {
            self.mcycle +%= 1;
        }
        if (self.mcounteren & 2 > 0) {
            self.time +%= 1;
        }
        if (self.mcounteren & 4 > 0 and buf.instruction != 0 and buf.exception == null) {
            self.minstret +%= 1;
        }
    }
};
