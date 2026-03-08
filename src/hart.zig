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
    rd: u5 = 0,
};

/// Keeps the result of the last Execute operation
const ExecuteBuffer = struct {
    instruction: u32 = 0,
    decoded: riscv.InstructionUnion = .{ .none = @as(void, undefined) },
    op1: u32 = 0,
    op2: u32 = 0,
    res: u32 = 0,
    addr: u32 = 0,
    rd: u5 = 0,
    fw_rd: u5 = 0,
    fw_res: u32 = 0,
};

// Writeback does not need to pass information to any other stage, so it doesn't get a buffer

pub const Hart = struct {
    registers: [32]u32 = [_]u32{0} ** 32,
    pc: u32 = 0,
    next_pc: u32 = 0,
    flush: u32 = 0,
    ebreak: bool = false,

    fetch_buf: FetchBuffer = .{},
    decode_buf: DecodeBuffer = .{},
    read_registers_buf: ReadRegistersBuffer = .{},
    execute_buf: ExecuteBuffer = .{},

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

    /// Debugging method to print the current Hart state to stderr
    pub fn printState(self: @This()) void {
        std.debug.print("pc: {x} ({0d})\n", .{self.pc});
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
    }

    // Emulation methods

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

        // 5. Writeback
        self.writeback(&self.execute_buf);

        // 4. Execute and Memory access
        self.execute_buf.instruction = self.read_registers_buf.instruction;
        self.execute_buf.decoded = self.read_registers_buf.decoded;
        self.execute_buf.op1 = self.read_registers_buf.op1;
        self.execute_buf.op2 = self.read_registers_buf.op2;
        self.execute_buf.rd = self.read_registers_buf.rd;
        self.execute(&self.execute_buf);
        //  pipeline forward for next execute
        self.execute_buf.fw_res = self.execute_buf.res;
        self.execute_buf.fw_rd = self.execute_buf.rd;

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
        self.flush -|= 1;
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

    /// Executes the instruction
    fn execute(self: *@This(), buf: *ExecuteBuffer) void {
        // After a branch or jump, the pipeline must be flushed, which invalidates instructions in the pipeline
        // that were not meant to be executed.
        if (self.flush > 0) {
            buf.instruction = 19; // This is the cannonical NOP
            buf.decoded = .{ .I = @bitCast(buf.instruction) };
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
                    else => {},
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
                    else => {},
                }
            },
            .S => |value| {
                switch (value.opcode) {
                    @intFromEnum(riscv.Opcode.STORE) => {
                        executeMemoryAccess(self, buf);
                    },
                    else => {},
                }
            },
            .B => |value| {
                switch (value.opcode) {
                    @intFromEnum(riscv.Opcode.BRANCH) => {
                        executeBranch(self, buf);
                    },
                    else => {},
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
                    else => {},
                }
            },
            .J => |value| {
                switch (value.opcode) {
                    @intFromEnum(riscv.Opcode.JAL) => {
                        executeJal(self, buf);
                    },
                    else => {},
                }
            },
            .none => {}, // TODO handle unimplemented or illegal instructions
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
                }
                // TODO handle illegal instructions
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
                } // TODO handle illegal instructions
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
                }
                // TODO handle illegal instructions
            },
        }
    }

    fn executeJal(self: *@This(), buf: *ExecuteBuffer) void {
        buf.res = self.pc -% 12 +% 4;
        self.next_pc = self.pc -% 12 +% riscv.getJImmediate(buf.instruction);
        self.flush = 4;
    }

    fn executeJalr(self: *@This(), buf: *ExecuteBuffer) void {
        buf.res = self.pc -% 12 +% 4;
        self.next_pc = riscv.getIImmediate(buf.instruction) +% buf.op1;
        self.flush = 4;
    }

    fn executeBranch(self: *@This(), buf: *ExecuteBuffer) void {
        const dest = self.pc -% 12 +% riscv.getBImmediate(buf.instruction);
        switch (buf.decoded.B.funct3) {
            riscv.Funct3.BRANCH.beq => {
                if (buf.op1 == buf.op2) self.next_pc = dest;
            },
            riscv.Funct3.BRANCH.bne => {
                if (buf.op1 != buf.op2) self.next_pc = dest;
            },
            riscv.Funct3.BRANCH.blt => {
                const rs1: i32 = @bitCast(buf.op1);
                const rs2: i32 = @bitCast(buf.op2);
                if (rs1 < rs2) self.next_pc = dest;
            },
            riscv.Funct3.BRANCH.bge => {
                const rs1: i32 = @bitCast(buf.op1);
                const rs2: i32 = @bitCast(buf.op2);
                if (rs1 >= rs2) self.next_pc = dest;
            },
            riscv.Funct3.BRANCH.bltu => {
                if (buf.op1 < buf.op2) self.next_pc = dest;
            },
            riscv.Funct3.BRANCH.bgeu => {
                if (buf.op1 >= buf.op2) self.next_pc = dest;
            },
            else => {}, // TODO handle illegal instructions
        }
    }

    /// Executes memory access operations like LOAD and STORE
    fn executeMemoryAccess(self: *@This(), buf: *ExecuteBuffer) void {
        const decoded: riscv.ITypeInstruction = @bitCast(buf.instruction);
        if (decoded.opcode == @intFromEnum(riscv.Opcode.LOAD)) {
            buf.addr = buf.op1 +% riscv.getIImmediate(buf.instruction);
            switch (buf.decoded.I.funct3) {
                riscv.Funct3.LOAD.lb, riscv.Funct3.LOAD.lbu => |value| {
                    buf.res = self.bus.load(buf.addr, 1);
                    if (value & 4 == 0 and buf.res >> 7 == 1) {
                        buf.res |= 0xFFFF_FF00;
                    }
                },
                riscv.Funct3.LOAD.lh, riscv.Funct3.LOAD.lhu => |value| {
                    buf.res = self.bus.load(buf.addr, 2);
                    if (value & 4 == 0 and buf.res >> 15 == 1) {
                        buf.res |= 0xFFFF_0000;
                    }
                },
                riscv.Funct3.LOAD.lw => {
                    buf.res = self.bus.load(buf.addr, 4);
                },
                else => {}, // TODO handle illegal width
            }
        } else if (decoded.opcode == @intFromEnum(riscv.Opcode.STORE)) {
            buf.addr = buf.op1 +% riscv.getSImmediate(buf.instruction);
            switch (buf.decoded.S.funct3) {
                riscv.Funct3.STORE.sb => {
                    self.bus.store(buf.addr, buf.op2, 1);
                },
                riscv.Funct3.STORE.sh => {
                    self.bus.store(buf.addr, buf.op2, 2);
                },
                riscv.Funct3.STORE.sw => {
                    self.bus.store(buf.addr, buf.op2, 4);
                },
                else => {}, // TODO handle illegal width
            }
        }
    }

    fn executeSystem(self: *@This(), buf: *ExecuteBuffer) void {
        const decoded = buf.decoded.I;
        if (decoded.imm == 0) {
            // ECALL
            // TODO
        } else if (decoded.imm == 1) {
            // EBREAK
            self.ebreak = true;
        } // TODO handle illegal values
    }

    /// Writes pipeline results to the register file
    fn writeback(self: *@This(), buf: *ExecuteBuffer) void {
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
