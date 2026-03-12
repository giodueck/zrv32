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
        .slli  = 0b001,
        .slti  = 0b010,
        .sltiu = 0b011,
        .xori  = 0b100,
        .srli  = 0b101,
        .srai  = 0b101,
        .ori   = 0b110,
        .andi  = 0b111,
    },
    .OP = .{
        .add   = 0b000,
        .sub   = 0b000,
        .sll   = 0b001,
        .slt   = 0b010,
        .sltu  = 0b011,
        .xor   = 0b100,
        .srl   = 0b101,
        .sra   = 0b101,
        .@"or" = 0b110,
        .@"and"= 0b111,
    },
    .BRANCH = .{
        .beq  = 0b000,
        .bne  = 0b001,
        .blt  = 0b100,
        .bge  = 0b101,
        .bltu = 0b110,
        .bgeu = 0b111,
    },
    .LOAD = .{
        .lb  = 0b000,
        .lh  = 0b001,
        .lw  = 0b010,
        .lbu = 0b100,
        .lhu = 0b101,
    },
    .STORE = .{
        .sb  = 0b000,
        .sh  = 0b001,
        .sw  = 0b010,
    },
    .SYSTEM = .{
        .priv   = 0b000,
        .csrrw  = 0b001,
        .csrrs  = 0b010,
        .csrrc  = 0b011,
        .csrrwi = 0b101,
        .csrrsi = 0b110,
        .csrrci = 0b111,
    }
};

pub const SystemImmediates = .{
    .ecall = 0,
    .ebreak = 1,
    .mret = 0b0011000_00010,
    .wfi = 0b0001000_00101,
};
// zig fmt: on

pub const NOP: u32 = 19;

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

pub const Traps = enum(u4) {
    None = 0,
    IllegalInstruction,
    EnvironmentCall,
    LoadAccessMisaligned,
    LoadAccessFault,
    StoreAccessMisaligned,
    StoreAccessFault,
    InstructionAccessFault,
    InstructionAddressMisaligned,
    Misc = 15,
    _,
};

pub const ExceptionCause = enum(u31) {
    InstructionAddressMisaligned = 0,
    InstructionAccessFault,
    IllegalInstruction,
    Breakpoint,
    LoadAddressMisaligned,
    LoadAccessFault,
    StoreAddressMisaligned,
    StoreAccessFault,
    EnvironmentCallUMode,
    EnvironmentCallSMode,
    EnvironmentCallMMode = 11,
    InstructionPageFault,
    LoadPageFault,
    StorePageFault = 15,
    DoubleTrap,
    SoftwareCheck = 18,
    HardwareError,
    // Some more custom and reserved
    _,
};

// While I only plan to implement User and Machine, this is the full list
pub const Priv = enum(u2) {
    User = 0,
    Supervisor = 1,
    Reserved = 2,
    Machine = 3,
};

/// CSR that keeps track of and controls the hart's current operating state.
/// WPRI fields are to be preserved when writing and ignored when reading.
pub const MStatus = packed struct(u32) {
    /// WPRI
    a: u1,
    /// Supervisor interrupt enable
    sie: u1,
    /// WPRI
    b: u1,
    /// Machine interrupt enable
    mie: u1,
    /// WPRI
    c: u1,
    /// Supervisor previous interrupt enable
    spie: u1,
    /// User big endian
    ube: u1,
    /// Machine previous interrupt enable
    mpie: u1,
    /// Supervisor previous privilege
    spp: u1,
    /// Vector status
    vs: u2,
    /// Machine previous privilege
    mpp: u2,
    /// Floating-point status
    fs: u2,
    /// User extension status
    xs: u2,
    /// Modify (memory) privilege
    mprv: u1,
    /// Supervisor-user memory access
    sum: u1,
    /// Make executable (memory) readable
    mxr: u1,
    /// Trap virtual memory
    tvm: u1,
    /// Timeout wait (trap WFI)
    tw: u1,
    // Trap SRET
    tsr: u1,
    // S-Mode previous expected landing pad
    spelp: u1,
    /// S-Mode disable trap
    sdt: u1,
    /// WPRI
    d: u6,
    /// (F/V/X) State dirty
    sd: u1,

    /// Sets all read-only fields to their original values and verifies WARL fields
    pub fn verify(self: *@This()) void {
        // Some fields are read-only 0, e.g. Supervisor related ones
        const RoZero = enum {
            sie,
            spie,
            spp,
            mprv, // because we don't implement this
            sum,
            mxr, // because we don't implement this
            ube,
            tvm,
            tsr,
            vs,
            fs,
            xs,
            sd,
            spelp,
        };
        inline for (@typeInfo(RoZero).@"enum".fields) |f| {
            @field(self, f.name) = 0;
        }

        // Some fields have legal values
        if (self.mpp != 0 and self.mpp != 3) self.mpp = 0;
    }
};

/// CSR that keeps track of and controls the hart's current operating state.
/// Generally contains the same fields the RV64 version has in its upper word.
/// WPRI fields are to be preserved when writing and ignored when reading.
pub const MStatusH = packed struct(u32) {
    /// WPRI
    a: u4,
    /// Supervisor big endian
    sbe: u1,
    /// Machine big endian
    mbe: u1,
    /// Guest virtual address
    gva: u1,
    /// Machine previous virtualization mode
    mpv: u1,
    /// WPRI
    b: u1,
    // M-Mode previous expected landing pad
    mpelp: u1,
    /// M-Mode disable trap
    mdt: u1,
    /// WPRI
    c: u21,

    /// Sets all read-only fields to their original values and verifies WARL fields
    pub fn verify(self: *@This()) void {
        // Some fields are read-only 0, e.g. Supervisor related ones
        const RoZero = enum {
            sbe,
            mbe,
            mpelp,
            gva,
            mpv,
        };
        inline for (@typeInfo(RoZero).@"enum".fields) |f| {
            @field(self, f.name) = 0;
        }
    }
};

pub const MTrapVector = packed struct(u32) {
    /// Mode: Direct, vectored or reserved. In this implementation, hard-coded to direct
    mode: u2,
    /// Vector base address
    base: u30,

    /// Sets all read-only fields to their original values and verifies WARL fields
    pub fn verify(self: *@This()) void {
        // Some fields are read-only 0
        const RoZero = enum {
            mode
        };
        inline for (@typeInfo(RoZero).@"enum".fields) |f| {
            @field(self, f.name) = 0;
        }
    }
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

/// Returns the J-Immediate generated from the instruction.
pub fn getJImmediate(instr: u32) u32 {
    const decoded: JTypeInstruction = @bitCast(instr);
    var ret: u32 = (@as(u32, decoded.imm0) << 1) + (@as(u32, decoded.imm1) << 11) + (@as(u32, decoded.imm2) << 12) + (@as(u32, @as(u1, @bitCast(decoded.imm3))) << 20);
    // Sign-extend
    if (instr >> 31 == 1) {
        ret |= @truncate(0xFFFF_FFFF << 21);
    }
    return ret;
}

pub fn getBImmediate(instr: u32) u32 {
    const decoded: BTypeInstruction = @bitCast(instr);
    var ret: u32 = (@as(u32, decoded.imm0) << 1) + (@as(u32, decoded.imm1) << 5) + (@as(u32, decoded.imm2) << 11) + (@as(u32, @as(u1, @bitCast(decoded.imm3))) << 12);
    // Sign-extend
    if (instr >> 31 == 1) {
        ret |= @truncate(0xFFFF_FFFF << 13);
    }
    return ret;
}

pub fn getSImmediate(instr: u32) u32 {
    const decoded: STypeInstruction = @bitCast(instr);
    var ret: u32 = @as(u32, decoded.imml) + (@as(u32, @as(u7, @bitCast(decoded.immh))) << 5);
    // Sign-extend
    if (instr >> 31 == 1) {
        ret |= @truncate(0xFFFF_FFFF << 13);
    }
    return ret;
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
    .add = .{ .func = assembleRType, .opcode = Opcode.OP, .funct3 = Funct3.OP.add, .funct7 = 0 },
    .sub = .{ .func = assembleRType, .opcode = Opcode.OP, .funct3 = Funct3.OP.add, .funct7 = 32 },
    .slt = .{ .func = assembleRType, .opcode = Opcode.OP, .funct3 = Funct3.OP.slt, .funct7 = 0 },
    .sltu = .{ .func = assembleRType, .opcode = Opcode.OP, .funct3 = Funct3.OP.sltu, .funct7 = 0 },
    .@"and" = .{ .func = assembleRType, .opcode = Opcode.OP, .funct3 = Funct3.OP.@"and", .funct7 = 0 },
    .@"or" = .{ .func = assembleRType, .opcode = Opcode.OP, .funct3 = Funct3.OP.@"or", .funct7 = 0 },
    .xor = .{ .func = assembleRType, .opcode = Opcode.OP, .funct3 = Funct3.OP.xor, .funct7 = 0 },
    .sll = .{ .func = assembleRType, .opcode = Opcode.OP, .funct3 = Funct3.OP.sll, .funct7 = 0 },
    .srl = .{ .func = assembleRType, .opcode = Opcode.OP, .funct3 = Funct3.OP.srl, .funct7 = 0 },
    .sra = .{ .func = assembleRType, .opcode = Opcode.OP, .funct3 = Funct3.OP.srl, .funct7 = 32 },
    .snez = .{ .func = assembleRType, .opcode = Opcode.OP, .funct3 = Funct3.OP.sltu, .funct7 = 0, .rs1 = 0 },
    .jal = .{ .func = assembleJType, .opcode = Opcode.JAL },
    .j = .{ .func = assembleJType, .opcode = Opcode.JAL, .rd = 0 },
    .jalr = .{ .func = assembleIType, .opcode = Opcode.JALR, .funct3 = 0 },
    .jr = .{ .func = assembleIType, .opcode = Opcode.JALR, .funct3 = 0, .rd = 0 },
    .ret = .{ .func = assembleIType, .opcode = Opcode.JALR, .funct3 = 0, .rd = 0, .rs1 = 1, .imm = 0 },
    .beq = .{ .func = assembleBType, .opcode = Opcode.BRANCH, .funct3 = Funct3.BRANCH.beq },
    .bne = .{ .func = assembleBType, .opcode = Opcode.BRANCH, .funct3 = Funct3.BRANCH.bne },
    .blt = .{ .func = assembleBType, .opcode = Opcode.BRANCH, .funct3 = Funct3.BRANCH.blt },
    .bgt = .{ .func = assembleBType, .opcode = Opcode.BRANCH, .funct3 = Funct3.BRANCH.blt, .invert = true },
    .bge = .{ .func = assembleBType, .opcode = Opcode.BRANCH, .funct3 = Funct3.BRANCH.bge },
    .ble = .{ .func = assembleBType, .opcode = Opcode.BRANCH, .funct3 = Funct3.BRANCH.bge, .invert = true },
    .bltu = .{ .func = assembleBType, .opcode = Opcode.BRANCH, .funct3 = Funct3.BRANCH.bltu },
    .bgtu = .{ .func = assembleBType, .opcode = Opcode.BRANCH, .funct3 = Funct3.BRANCH.bltu, .invert = true },
    .bgeu = .{ .func = assembleBType, .opcode = Opcode.BRANCH, .funct3 = Funct3.BRANCH.bgeu },
    .bleu = .{ .func = assembleBType, .opcode = Opcode.BRANCH, .funct3 = Funct3.BRANCH.bgeu, .invert = true },
    .lb = .{ .func = assembleIType, .opcode = Opcode.LOAD, .funct3 = Funct3.LOAD.lb },
    .lh = .{ .func = assembleIType, .opcode = Opcode.LOAD, .funct3 = Funct3.LOAD.lh },
    .lw = .{ .func = assembleIType, .opcode = Opcode.LOAD, .funct3 = Funct3.LOAD.lw },
    .lbu = .{ .func = assembleIType, .opcode = Opcode.LOAD, .funct3 = Funct3.LOAD.lbu },
    .lhu = .{ .func = assembleIType, .opcode = Opcode.LOAD, .funct3 = Funct3.LOAD.lhu },
    .sw = .{ .func = assembleSType, .opcode = Opcode.STORE, .funct3 = Funct3.STORE.sw },
    .sh = .{ .func = assembleSType, .opcode = Opcode.STORE, .funct3 = Funct3.STORE.sh },
    .sb = .{ .func = assembleSType, .opcode = Opcode.STORE, .funct3 = Funct3.STORE.sb },
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
    const rd = if (@hasField(@TypeOf(info), "rd")) info.rd else parseRegister(args.next() orelse unreachable);
    const rs1 = if (@hasField(@TypeOf(info), "rs1")) info.rs1 else parseRegister(args.next() orelse unreachable);
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
            break :a info.imm;
        }
        const parsed = std.fmt.parseInt(i20, args.next() orelse unreachable, 10) catch unreachable;
        break :a parsed;
    };

    return @bitCast(UTypeInstruction{
        .opcode = @intFromEnum(info.opcode),
        .rd = rd,
        .imm = imm,
    });
}

fn assembleRType(comptime args: *std.mem.TokenIterator(u8, .any), comptime info: anytype) u32 {
    const rd = parseRegister(args.next() orelse unreachable);
    const rs1 = if (@hasField(@TypeOf(info), "rs1")) info.rs1 else parseRegister(args.next() orelse unreachable);
    const rs2 = parseRegister(args.next() orelse unreachable);

    return @bitCast(RTypeInstruction{
        .opcode = @intFromEnum(info.opcode),
        .rd = rd,
        .rs1 = rs1,
        .rs2 = rs2,
        .funct3 = info.funct3,
        .funct7 = info.funct7,
    });
}

fn assembleJType(comptime args: *std.mem.TokenIterator(u8, .any), comptime info: anytype) u32 {
    const rd = if (@hasField(@TypeOf(info), "rd")) info.rd else parseRegister(args.next() orelse unreachable);
    const imm = comptime a: {
        if (@hasField(@TypeOf(info), "imm")) {
            if (info.imm & 1 != 0) @compileError("Immediate must have 1 least-significant bit 0");
            break :a info.imm;
        }
        const parsed = std.fmt.parseInt(i21, args.next() orelse unreachable, 10) catch unreachable;
        if (parsed & 1 != 0) @compileError("Immediate must have 1 least-significant bit 0");
        break :a parsed;
    };

    return @bitCast(JTypeInstruction{
        .opcode = @intFromEnum(info.opcode),
        .rd = rd,
        .imm0 = @truncate(@as(u21, @bitCast(imm)) >> 1),
        .imm1 = @truncate(@as(u21, @bitCast(imm)) >> 11),
        .imm2 = @truncate(@as(u21, @bitCast(imm)) >> 12),
        .imm3 = @truncate(imm >> 20),
    });
}

fn assembleBType(comptime args: *std.mem.TokenIterator(u8, .any), comptime info: anytype) u32 {
    const rs1 = parseRegister(args.next() orelse unreachable);
    const rs2 = parseRegister(args.next() orelse unreachable);
    const imm = comptime a: {
        if (@hasField(@TypeOf(info), "imm")) {
            if (info.imm & 1 != 0) @compileError("Immediate must have 1 least-significant bit 0");
            break :a info.imm;
        }
        const parsed = std.fmt.parseInt(i13, args.next() orelse unreachable, 10) catch unreachable;
        if (parsed & 1 != 0) @compileError("Immediate must have 1 least-significant bit 0");
        break :a parsed;
    };
    const invert = if (@hasField(@TypeOf(info), "invert") and info.invert) true else false;
    return @bitCast(BTypeInstruction{
        .opcode = @intFromEnum(info.opcode),
        .rs1 = if (!invert) rs1 else rs2,
        .rs2 = if (!invert) rs2 else rs1,
        .funct3 = info.funct3,
        .imm0 = @truncate(@as(u13, @bitCast(imm)) >> 1),
        .imm1 = @truncate(@as(u13, @bitCast(imm)) >> 5),
        .imm2 = @truncate(@as(u13, @bitCast(imm)) >> 11),
        .imm3 = @truncate(imm >> 12),
    });
}

fn assembleSType(comptime args: *std.mem.TokenIterator(u8, .any), comptime info: anytype) u32 {
    const rs1 = parseRegister(args.next() orelse unreachable);
    const rs2 = parseRegister(args.next() orelse unreachable);
    const imm = comptime a: {
        if (@hasField(@TypeOf(info), "imm")) {
            break :a info.imm;
        }
        break :a std.fmt.parseInt(i12, args.next() orelse unreachable, 10) catch unreachable;
    };
    return @bitCast(STypeInstruction{
        .opcode = @intFromEnum(info.opcode),
        .rs1 = rs1,
        .rs2 = rs2,
        .funct3 = info.funct3,
        .imml = @truncate(@as(u12, @bitCast(imm))),
        .immh = @truncate(imm >> 5),
    });
}

fn pack(comptime args: *std.mem.TokenIterator(u8, .any), comptime info: anytype) u32 {
    // Don't want to have a nop with arguments!
    comptime std.debug.assert(args.next() == null);
    return @bitCast(info.unpacked);
}
