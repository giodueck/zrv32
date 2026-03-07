//! A Hart is to Risc-V what a Core is to x86. It is a distinct processing unit.

const std = @import("std");
const bus = @import("bus.zig");
const riscv = @import("riscv.zig");

/// Keeps the result of the last Fetch operation
const FetchBuffer = struct {
    instruction: u32 = 0,
};

/// Keeps the result of the last Decode operation
const DecodeBuffer = struct {
    instruction: u32 = 0,
    decoded: riscv.InstructionUnion = .{ .none = @as(void, undefined) },
};

/// Keeps the result of the last Read Registers operation
const ReadRegistersBuffer = struct {
    instruction: u32 = 0,
    decoded: riscv.InstructionUnion = .{ .none = @as(void, undefined) },
    op1: u32 = 0,
    op2: u32 = 0,
};

/// Keeps the result of the last Execute operation
const ExecuteBuffer = struct {
    instruction: u32 = 0,
    decoded: riscv.InstructionUnion = .{ .none = @as(void, undefined) },
    op1: u32 = 0,
    op2: u32 = 0,
    res: u32 = 0,
};

/// Keeps the result of the last Memory Access operation
const MemoryAccessBuffer = struct {
    instruction: u32 = 0,
    decoded: riscv.InstructionUnion = .{ .none = @as(void, undefined) },
    op1: u32 = 0,
    op2: u32 = 0,
    res: u32 = 0,
};

// Writeback does not need to pass information to any other stage, so it doesn't get a buffer

pub const Hart = struct {
    registers: [32]u32 = [_]u32{0} ** 32,
    pc: u32 = 0,
    next_pc: u32 = 0,

    fetch_buf: FetchBuffer = .{},
    decode_buf: DecodeBuffer = .{},
    read_registers_buf: ReadRegistersBuffer = .{},
    execute_buf: ExecuteBuffer = .{},
    memory_access_buf: MemoryAccessBuffer = .{},

    bus: bus.Bus = .{},

    allocator: std.mem.Allocator = undefined,

    pub fn init(self: *@This(), allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        try self.bus.init(self.allocator);
    }

    pub fn deinit(self: @This()) void {
        self.bus.deinit();
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
        self.memory_access_buf = MemoryAccessBuffer{};

        self.bus.set(self.bus.boot_rom_start, instr, 4);
        self.pc = self.bus.boot_rom_start;

        inline for (0..6) |_| {
            self.step();
        }
    }

    /// Load a slice of encoded instructions, flush the pipeline, then step through until every pipeline step
    /// ran the program
    pub fn execMany(self: *@This(), program: []u32) void {
        self.fetch_buf = FetchBuffer{};
        self.decode_buf = DecodeBuffer{};
        self.read_registers_buf = ReadRegistersBuffer{};
        self.execute_buf = ExecuteBuffer{};
        self.memory_access_buf = MemoryAccessBuffer{};

        self.loadROM(program);
        self.pc = self.bus.boot_rom_start;

        // Pipeline overhead
        inline for (0..5) |_| {
            self.step();
        }

        for (program) |_| {
            self.step();
        }
    }

    // Emulation methods

    /// Loads the program ROM. Fails silently, TODO don't
    pub fn loadROM(self: *@This(), rom: []const u32) void {
        for (rom, 0..) |word, i| {
            self.bus.set(self.bus.boot_rom_start + @as(u32, @intCast(i * 4)), word, 4);
        }
    }

    /// Sets the register rn to the value val, then sets x0 to 0.
    fn setReg(self: *@This(), rn: u5, val: u32) void {
        self.registers[rn] = val;
        self.registers[0] = 0;
    }

    /// Run a single cycle of the CPU, advancing each pipeline stage once
    pub fn step(self: *@This()) void {
        self.next_pc = self.pc +% 4;
        // Pipeline detail: writeback needs to finish before reading registers begins.
        // Since we want to use all buffers before writing to them, we do them in reverse order anyways

        // 6. Writeback
        self.writeback(&self.memory_access_buf);

        // 5. Memory access
        self.memory_access_buf.instruction = self.execute_buf.instruction;
        self.memory_access_buf.instruction = self.execute_buf.instruction;
        self.memory_access_buf.decoded = self.execute_buf.decoded;
        self.memory_access_buf.op1 = self.execute_buf.op1;
        self.memory_access_buf.op2 = self.execute_buf.op2;
        self.memory_access_buf.res = self.execute_buf.res;
        self.memoryAccess(&self.memory_access_buf);

        // 4. Execute
        self.execute_buf.instruction = self.read_registers_buf.instruction;
        self.execute_buf.decoded = self.read_registers_buf.decoded;
        self.execute_buf.op1 = self.read_registers_buf.op1;
        self.execute_buf.op2 = self.read_registers_buf.op2;
        self.execute(&self.execute_buf);

        // 3. Read registers
        self.read_registers_buf.instruction = self.decode_buf.instruction;
        self.read_registers_buf.decoded = self.decode_buf.decoded;
        self.readRegisters(&self.read_registers_buf);

        // 2. Decode
        self.decode_buf.instruction = self.fetch_buf.instruction;
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
        self.fetch_buf.instruction = self.bus.fetch(self.pc);

        self.pc = self.next_pc;
    }

    /// Reads the needed registers into the Read Registers step buffer.
    fn readRegisters(self: *@This(), buf: *ReadRegistersBuffer) void {
        buf.op1 = 0;
        buf.op2 = 0;
        switch (buf.decoded) {
            .R => |value| {
                buf.op1 = self.registers[value.rs1];
                buf.op2 = self.registers[value.rs2];
            },
            .I => |value| {
                buf.op1 = self.registers[value.rs1];
            },
            .S => |value| {
                buf.op1 = self.registers[value.rs1];
                buf.op2 = self.registers[value.rs2];
            },
            .B => |value| {
                buf.op1 = self.registers[value.rs1];
                buf.op2 = self.registers[value.rs2];
            },
            .U, .J => {},
            else => {},
        }
    }

    /// Executes the instruction
    fn execute(self: *@This(), buf: *ExecuteBuffer) void {
        buf.res = 0;
        // TODO finish
        switch (buf.decoded) {
            .R => {},
            .I => |value| {
                switch (value.opcode) {
                    @intFromEnum(riscv.Opcode.LOAD) => {},
                    @intFromEnum(riscv.Opcode.MISC_MEM) => {},
                    @intFromEnum(riscv.Opcode.OP_IMM) => {
                        executeOpImm(self, buf);
                    },
                    @intFromEnum(riscv.Opcode.JALR) => {},
                    @intFromEnum(riscv.Opcode.SYSTEM) => {},
                    else => {}, // TODO handle unimplemented or illegal instructions
                }
            },
            .S => {},
            .B => {},
            .U => {},
            .J => {},
            else => {},
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
            // TODO finish
            else => {},
        }
    }

    /// Executes memory access operations like LOAD and STORE
    fn memoryAccess(self: *@This(), buf: *MemoryAccessBuffer) void {
        _ = self;
        _ = buf;
    }

    /// Writes pipeline results to the register file
    fn writeback(self: *@This(), buf: *MemoryAccessBuffer) void {
        var rd: u5 = 0;
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
        if (rd != 0) {
            self.setReg(rd, buf.res);
        }
    }
};
