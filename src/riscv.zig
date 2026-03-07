const std = @import("std");

// zig fmt: off
pub const RTypeInstruction = packed struct(u32) {
    opcode: u7,
    rd: u5,
    funct3: u3,
    rs1: u5,
    rs2: u5,
    funct7: u7,
};

pub const ITypeInstruction = packed struct(u32) {
    opcode: u7,
    rd: u5,
    funct3: u3,
    rs1: u5,
    imm: i12,
};

pub const STypeInstruction = packed struct(u32) {
    opcode: u7,
    imml: u5,   // imm[0:4]
    funct3: u3,
    rs1: u5,
    rs2: u5,
    immh: i7,   // imm[5:11]
};

pub const BTypeInstruction = packed struct(u32) {
    opcode: u7,
    imm2: u1,   // imm[11]
    imm0: u4,   // imm[1:4]
    funct3: u3,
    rs1: u5,
    rs2: u5,
    imm1: u6,   // imm[5:10]
    imm3: i1,   // imm[12]
};

pub const UTypeInstruction = packed struct(u32) {
    opcode: u7,
    rd: u5,
    imm: i20,   // imm[12:31]
};

pub const JTypeInstruction = packed struct(u32) {
    opcode: u7,
    rd: u5,
    imm2: u8,   // imm[12:19]
    imm1: u1,   // imm[11]
    imm0: u10,  // imm[1:10]
    imm3: i1,   // imm[20]
};

pub const InstructionTypeTag = enum { R, I, S, B, U, J, none };

pub const InstructionUnion = union(InstructionTypeTag) {
    R: RTypeInstruction,
    I: ITypeInstruction,
    S: STypeInstruction,
    B: BTypeInstruction,
    U: UTypeInstruction,
    J: JTypeInstruction,
    none: void,
};

pub const Opcode = enum(u7) {
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

    pub fn getType(self: @This()) InstructionTypeTag {
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

pub const Funct3 = .{
    .OP_IMM = .{
        .addi  = 0b000,
        .slti  = 0b010,
        .sltiu = 0b011,
        .xori  = 0b100,
        .ori   = 0b110,
        .andi  = 0b111,
        .slli  = 0b001,
        .srli  = 0b101,
        .srai  = 0b101,
    },
};

// zig fmt: on
pub const RegisterNames = .{
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
pub const RegisterAliases = .{
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

/// Returns the I-Immediate generated from the instruction.
pub fn getIImmediate(instr: u32) u32 {
    var ret: u32 = instr >> 20;
    // Sign-extend
    if (instr >> 31 == 1) {
        ret |= @truncate(0xFFFF_FFFF << 12);
    }
    return ret;
}

/// Returns the U-Immediate generated from the instruction.
pub inline fn getUImmediate(instr: u32) u32 {
    return instr & 0xFFFF_F000;
}

// For testing

pub fn assemble(comptime instr: []const u8) u32 {
    comptime var args = std.mem.tokenizeAny(u8, instr, " ,");
    const mnemonic = comptime args.next().?;

    const info = @field(instructions, mnemonic);
    return comptime info.func(&args, info);
}

/// Lookup table to determine how to interpret/assemble each instruction (for test assembly like "addi x1,x0,42"
const instructions = .{
    .addi = .{ .func = assembleIType, .opcode = Opcode.OP_IMM, .funct3 = Funct3.OP_IMM.addi },
    .mv = .{ .func = assembleIType, .opcode = Opcode.OP_IMM, .funct3 = Funct3.OP_IMM.addi, .imm = 0 },
    .nop = .{ .func = pack, .unpacked = ITypeInstruction{ .opcode = @intFromEnum(Opcode.OP_IMM), .funct3 = Funct3.OP_IMM.addi, .rd = 0, .rs1 = 0, .imm = 0 } },
    .slti = .{ .func = assembleIType, .opcode = Opcode.OP_IMM, .funct3 = Funct3.OP_IMM.slti },
    .sltiu = .{ .func = assembleIType, .opcode = Opcode.OP_IMM, .funct3 = Funct3.OP_IMM.sltiu },
    .seqz = .{ .func = assembleIType, .opcode = Opcode.OP_IMM, .funct3 = Funct3.OP_IMM.sltiu, .imm = 1 },
    .andi = .{ .func = assembleIType, .opcode = Opcode.OP_IMM, .funct3 = Funct3.OP_IMM.andi },
    .ori = .{ .func = assembleIType, .opcode = Opcode.OP_IMM, .funct3 = Funct3.OP_IMM.ori },
    .xori = .{ .func = assembleIType, .opcode = Opcode.OP_IMM, .funct3 = Funct3.OP_IMM.xori },
    .not = .{ .func = assembleIType, .opcode = Opcode.OP_IMM, .funct3 = Funct3.OP_IMM.xori, .imm = -1 },
    .slli = .{ .func = assembleITypeShift, .opcode = Opcode.OP_IMM, .funct3 = Funct3.OP_IMM.slli },
    .srli = .{ .func = assembleITypeShift, .opcode = Opcode.OP_IMM, .funct3 = Funct3.OP_IMM.srli },
    .srai = .{ .func = assembleITypeShift, .opcode = Opcode.OP_IMM, .funct3 = Funct3.OP_IMM.srai, .arithmetic = true },
    .lui = .{ .func = assembleUType, .opcode = Opcode.LUI },
    .auipc = .{ .func = assembleUType, .opcode = Opcode.AUIPC },
};

fn parseRegister(comptime name: []const u8) u5 {
    if (@hasField(@TypeOf(RegisterNames), name)) {
        return @field(RegisterNames, name);
    } else if (@hasField(@TypeOf(RegisterAliases), name)) {
        return @field(RegisterAliases, name);
    }

    @compileError("Unrecognized register name: " ++ name);
}

fn assembleIType(comptime args: *std.mem.TokenIterator(u8, .any), comptime info: anytype) u32 {
    const rd = parseRegister(args.next() orelse unreachable);
    const rs1 = parseRegister(args.next() orelse unreachable);
    const imm = comptime a: {
        if (@hasField(@TypeOf(info), "imm")) {
            break :a info.imm;
        }
        break :a std.fmt.parseInt(i12, args.next() orelse unreachable, 10) catch unreachable;
    };
    comptime std.debug.assert(args.next() == null);

    return @bitCast(ITypeInstruction{
        .opcode = @intFromEnum(info.opcode),
        .rd = rd,
        .funct3 = info.funct3,
        .rs1 = rs1,
        .imm = imm,
    });
}

fn assembleITypeShift(comptime args: *std.mem.TokenIterator(u8, .any), comptime info: anytype) u32 {
    const rd = parseRegister(args.next() orelse unreachable);
    const rs1 = parseRegister(args.next() orelse unreachable);
    const imm = comptime a: {
        if (@hasField(@TypeOf(info), "imm")) {
            break :a info.imm;
        }
        break :a std.fmt.parseInt(u5, args.next() orelse unreachable, 10) catch unreachable;
    };
    const imm_upper: u12 = if (@hasField(@TypeOf(info), "arithmetic") and info.arithmetic) 0b0100000 else 0;
    comptime std.debug.assert(args.next() == null);

    return @bitCast(ITypeInstruction{
        .opcode = @intFromEnum(info.opcode),
        .rd = rd,
        .funct3 = info.funct3,
        .rs1 = rs1,
        .imm = imm | (imm_upper << 5),
    });
}

fn assembleUType(comptime args: *std.mem.TokenIterator(u8, .any), comptime info: anytype) u32 {
    const rd = parseRegister(args.next() orelse unreachable);
    const imm = comptime a: {
        if (@hasField(@TypeOf(info), "imm")) {
            if (info.imm & 0xFFF != 0) @compileError("Immediate must have 12 least-significant bits 0");
            break :a info.imm;
        }
        const parsed = std.fmt.parseInt(i32, args.next() orelse unreachable, 10) catch unreachable;
        if (parsed & 0xFFF != 0) @compileError("Immediate must have 12 least-significant bits 0");
        break :a parsed;
    };

    return @bitCast(UTypeInstruction{
        .opcode = @intFromEnum(info.opcode),
        .rd = rd,
        .imm = @truncate(imm >> 12),
    });
}

fn pack(comptime args: *std.mem.TokenIterator(u8, .any), comptime info: anytype) u32 {
    // Don't want to have a nop with arguments!
    comptime std.debug.assert(args.next() == null);
    return @bitCast(info.unpacked);
}
