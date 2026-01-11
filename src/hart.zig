//! A Hart is to Risc-V what a Core is to x86. It is a distinct processing unit.

const std = @import("std");
const bus = @import("bus.zig");

// zig fmt: off
const RTypeInstruction = packed struct(u32) {
    opcode: u7,
    rd: u5,
    funct3: u3,
    rs1: u5,
    rs2: u5,
    funct7: u7,
};

const ITypeInstruction = packed struct(u32) {
    opcode: u7,
    rd: u5,
    funct3: u3,
    rs1: u5,
    imm: i12,
};

const STypeInstruction = packed struct(u32) {
    opcode: u7,
    imml: u5,   // imm[0:4]
    funct3: u3,
    rs1: u5,
    rs2: u5,
    immh: i7,   // imm[5:11]
};

const BTypeInstruction = packed struct(u32) {
    opcode: u7,
    imm2: u1,   // imm[11]
    imm0: u4,   // imm[1:4]
    funct3: u3,
    rs1: u5,
    rs2: u5,
    imm1: u6,   // imm[5:10]
    imm3: i1,   // imm[12]
};

const UTypeInstruction = packed struct(u32) {
    opcode: u7,
    rd: u5,
    imm: i20,   // imm[12:31]
};

const JTypeInstruction = packed struct(u32) {
    opcode: u7,
    rd: u5,
    imm2: u8,   // imm[12:19]
    imm1: u1,   // imm[11]
    imm0: u10,  // imm[1:10]
    imm3: i1,   // imm[20]
};

const InstructionTypeTag = enum { R, I, S, B, U, J, none };

const InstructionUnion = union(InstructionTypeTag) {
    R: RTypeInstruction,
    I: ITypeInstruction,
    S: STypeInstruction,
    B: BTypeInstruction,
    U: UTypeInstruction,
    J: JTypeInstruction,
    none: void,
};

const Opcode = enum(u7) {
    LOAD        = 0b0000011,
    MISC_MEM    = 0b0001111,
    OP_IMM      = 0b0010011,
    AUIPC       = 0b0010111,
    STORE       = 0b0100011,
    OP          = 0b0110011,
    LUI         = 0b0110111,
    BRANCH      = 0b1100011,
    JALR        = 0b1100111,
    JAL         = 0b1101111,
    SYSTEM      = 0b1110011,
    _,

    fn getType(self: @This()) InstructionTypeTag {
        return switch (self) {
            .OP => .R,
            .LOAD, .MISC_MEM, .OP_IMM, .JALR, .SYSTEM => .I,
            .STORE => .S,
            .BRANCH => .B,
            .LUI, .AUIPC => .U,
            .JAL => .J,
            else => .none,
        };
    }
};
// zig fmt: on

/// Lookup table to determine how to interpret/assemble each instruction (for test assembly like "addi x1,x0,42"
const instructions = .{
    // TODO
    .add = .{},
};

/// Keeps the result of the last Fetch operation
const FetchBuffer = struct {
    instruction: u32 = 0,
};

/// Keeps the result of the last Decode operation
const DecodeBuffer = struct {
    instruction: u32 = 0,
    decoded: InstructionUnion = .{ .none = @as(void, undefined) },
};

/// Keeps the result of the last Read Registers operation
const ReadRegistersBuffer = struct {
    instruction: u32 = 0,
    decoded: InstructionUnion = .{ .none = @as(void, undefined) },
    op1: u32 = 0,
    op2: u32 = 0,
};

/// Keeps the result of the last Execute operation
const ExecuteBuffer = struct {
    instruction: u32 = 0,
};

/// Keeps the result of the last Memory Access operation
const MemoryAccessBuffer = struct {
    instruction: u32 = 0,
};

// Writeback does not need to pass information to any other stage, so it doesn't get a buffer

const RegisterNames = .{
    .x0 = 0,
    .x1 = 1,
    .x2 = 2,
    .x3 = 3,
    .x4 = 4,
    .x5 = 5,
    .x6 = 6,
    .x7 = 7,
    .x8 = 8,
    .x9 = 9,
    .x10 = 10,
    .x11 = 11,
    .x12 = 12,
    .x13 = 13,
    .x14 = 14,
    .x15 = 15,
    .x16 = 16,
    .x17 = 17,
    .x18 = 18,
    .x19 = 19,
    .x20 = 20,
    .x21 = 21,
    .x22 = 22,
    .x23 = 23,
    .x24 = 24,
    .x25 = 25,
    .x26 = 26,
    .x27 = 27,
    .x28 = 28,
    .x29 = 29,
    .x30 = 30,
    .x31 = 31,
};

/// When not using xN for a register name, these are the aliases to use
const RegisterAliases = .{
    .zero = 0,
    .ra = 1,
    .sp = 2,
    .gp = 3,
    .tp = 4,
    .t0 = 5,
    .t1 = 6,
    .t2 = 7,
    .s0 = 8,
    .s1 = 9,
    .a0 = 10,
    .a1 = 11,
    .a2 = 12,
    .a3 = 13,
    .a4 = 14,
    .a5 = 15,
    .a6 = 16,
    .a7 = 17,
    .s2 = 18,
    .s3 = 19,
    .s4 = 20,
    .s5 = 21,
    .s6 = 22,
    .s7 = 23,
    .s8 = 24,
    .s9 = 25,
    .s10 = 26,
    .s11 = 27,
    .t3 = 28,
    .t4 = 29,
    .t5 = 30,
    .t6 = 31,
};

pub const Hart = struct {
    registers: [32]u32 = [_]u32{0} ** 32,
    pc: u32 = 0,
    next_pc: u32 = 0,

    fetch_buf: FetchBuffer = .{},
    decode_buf: DecodeBuffer = .{},
    read_registers_buf: ReadRegistersBuffer = .{},
    execute_buf: ExecuteBuffer = .{},
    memory_access_buf: MemoryAccessBuffer = .{},

    bus: bus.Bus = undefined,

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
            if (@hasField(@TypeOf(RegisterNames), field.name)) {
                index = @field(RegisterNames, field.name);
            } else if (@hasField(@TypeOf(RegisterAliases), field.name)) {
                index = @field(RegisterAliases, field.name);
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
            if (@hasField(@TypeOf(RegisterNames), field.name)) {
                index = @field(RegisterNames, field.name);
            } else if (@hasField(@TypeOf(RegisterAliases), field.name)) {
                index = @field(RegisterAliases, field.name);
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

    // Emulation methods

    /// Loads the program ROM. Fails silently, TODO don't
    pub fn loadROM(self: *@This(), rom: []const u32) void {
        for (rom, 0..) |word, i| {
            self.bus.set(bus.BootRomStart + @as(u32, @intCast(i * 4)), word, 4);
        }
    }

    /// Sets the register rn to the value val, then sets x0 to 0.
    fn setReg(self: @This(), rn: u5, val: u32) void {
        self.registers[rn] = val;
        self.registers[0] = 0;
    }

    /// Run a single cycle of the CPU, advancing each pipeline stage once
    pub fn step(self: *@This()) void {
        self.next_pc = self.pc +% 4;
        // Pipeline detail: writeback needs to finish before reading registers begins.
        // Since we want to use all buffers before writing to them, we do them in reverse order anyways

        // 6. Writeback

        // 5. Memory access
        self.memory_access_buf.instruction = self.execute_buf.instruction;

        // 4. Execute
        self.execute_buf.instruction = self.read_registers_buf.instruction;

        // 3. Read registers
        self.read_registers_buf.instruction = self.decode_buf.instruction;
        self.read_registers_buf.decoded = self.decode_buf.decoded;
        self.readRegisters(&self.read_registers_buf);
        std.debug.print("{any}\n", .{self.read_registers_buf});

        // 2. Decode
        self.decode_buf.instruction = self.fetch_buf.instruction;
        const decode_r: RTypeInstruction = @bitCast(self.decode_buf.instruction);
        const decode_ins_type = Opcode.getType(@enumFromInt(decode_r.opcode));
        switch (decode_ins_type) {
            .R => self.decode_buf.decoded = .{ .R = @bitCast(self.decode_buf.instruction) },
            .I => self.decode_buf.decoded = .{ .I = @bitCast(self.decode_buf.instruction) },
            .S => self.decode_buf.decoded = .{ .S = @bitCast(self.decode_buf.instruction) },
            .B => self.decode_buf.decoded = .{ .B = @bitCast(self.decode_buf.instruction) },
            .U => self.decode_buf.decoded = .{ .U = @bitCast(self.decode_buf.instruction) },
            .J => self.decode_buf.decoded = .{ .J = @bitCast(self.decode_buf.instruction) },
            else => self.decode_buf.decoded = .{ .none = @as(void, undefined) },
        }
        std.debug.print("{any}\n", .{self.decode_buf});

        // 1. Fetch
        self.fetch_buf.instruction = self.bus.fetch(self.pc);
        std.debug.print("{any}\n", .{self.fetch_buf});

        self.pc = self.next_pc;
    }

    /// Reads the needed registers into the Read Registers step buffer.
    fn readRegisters(self: *@This(), buf: *ReadRegistersBuffer) void {
        switch (buf.decoded) {
            .R, => |value| {
                buf.op1 = self.registers[value.rs1];
                buf.op2 = self.registers[value.rs2];
            },
            .I, => |value| {
                buf.op1 = self.registers[value.rs1];
                buf.op2 = 0;
            },
            .S, => |value| {
                buf.op1 = self.registers[value.rs1];
                buf.op2 = self.registers[value.rs2];
            },
            .B, => |value| {
                buf.op1 = self.registers[value.rs1];
                buf.op2 = self.registers[value.rs2];
            },
            .U, => |value| {
                _ = value;
                buf.op1 = 0;
                buf.op2 = 0;
            },
            .J, => |value| {
                _ = value;
                buf.op1 = 0;
                buf.op2 = 0;
            },
            else => {}
        }
    }
};
