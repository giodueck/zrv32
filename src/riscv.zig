const std = @import("std");

pub const ISA = "RV32I_Zicsr";

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

// zig fmt: on

pub const PrivImmediates = .{
    .ecall = 0,
    .ebreak = 1,
    .mret = 0b0011000_00010,
    .wfi = 0b0001000_00101,
};

pub const CsrPriv = struct {
    priv: Priv,
    write: bool = false,
    /// True if a CSR must exist but is implemented as read-only 0
    zero: bool = false,
};

pub const CsrNumber = enum(u12) {
    cycle = 0xC00,
    time,
    instret,
    hpmcounter3,
    hpmcounter4,
    hpmcounter5,
    hpmcounter6,
    hpmcounter7,
    hpmcounter8,
    hpmcounter9,
    hpmcounter10,
    hpmcounter11,
    hpmcounter12,
    hpmcounter13,
    hpmcounter14,
    hpmcounter15,
    hpmcounter16,
    hpmcounter17,
    hpmcounter18,
    hpmcounter19,
    hpmcounter20,
    hpmcounter21,
    hpmcounter22,
    hpmcounter23,
    hpmcounter24,
    hpmcounter25,
    hpmcounter26,
    hpmcounter27,
    hpmcounter28,
    hpmcounter29,
    hpmcounter30,
    hpmcounter31,
    cycleh = 0xC80,
    timeh,
    instreth,
    hpmcounter3h,
    hpmcounter4h,
    hpmcounter5h,
    hpmcounter6h,
    hpmcounter7h,
    hpmcounter8h,
    hpmcounter9h,
    hpmcounter10h,
    hpmcounter11h,
    hpmcounter12h,
    hpmcounter13h,
    hpmcounter14h,
    hpmcounter15h,
    hpmcounter16h,
    hpmcounter17h,
    hpmcounter18h,
    hpmcounter19h,
    hpmcounter20h,
    hpmcounter21h,
    hpmcounter22h,
    hpmcounter23h,
    hpmcounter24h,
    hpmcounter25h,
    hpmcounter26h,
    hpmcounter27h,
    hpmcounter28h,
    hpmcounter29h,
    hpmcounter30h,
    hpmcounter31h,

    mvendorid = 0xF11,
    marchid,
    mimpid,
    mhartid,
    mconfigptr,

    mstatus = 0x300,
    misa,
    mie = 0x304,
    mtvec,
    mcounteren,
    mstatush = 0x310,

    mscratch = 0x340,
    mepc,
    mcause,
    mtval,
    mip,
    mtinst = 0x34A,

    menvcfg = 0x30A,
    menvcfgh = 0x31A,

    mcycle = 0xB00,
    minstret = 0xB02,
    mhpmcounter3,
    mhpmcounter4,
    mhpmcounter5,
    mhpmcounter6,
    mhpmcounter7,
    mhpmcounter8,
    mhpmcounter9,
    mhpmcounter10,
    mhpmcounter11,
    mhpmcounter12,
    mhpmcounter13,
    mhpmcounter14,
    mhpmcounter15,
    mhpmcounter16,
    mhpmcounter17,
    mhpmcounter18,
    mhpmcounter19,
    mhpmcounter20,
    mhpmcounter21,
    mhpmcounter22,
    mhpmcounter23,
    mhpmcounter24,
    mhpmcounter25,
    mhpmcounter26,
    mhpmcounter27,
    mhpmcounter28,
    mhpmcounter29,
    mhpmcounter30,
    mhpmcounter31,
    mcycleh = 0xB80,
    minstreth = 0xB82,
    mhpmcounter3h,
    mhpmcounter4h,
    mhpmcounter5h,
    mhpmcounter6h,
    mhpmcounter7h,
    mhpmcounter8h,
    mhpmcounter9h,
    mhpmcounter10h,
    mhpmcounter11h,
    mhpmcounter12h,
    mhpmcounter13h,
    mhpmcounter14h,
    mhpmcounter15h,
    mhpmcounter16h,
    mhpmcounter17h,
    mhpmcounter18h,
    mhpmcounter19h,
    mhpmcounter20h,
    mhpmcounter21h,
    mhpmcounter22h,
    mhpmcounter23h,
    mhpmcounter24h,
    mhpmcounter25h,
    mhpmcounter26h,
    mhpmcounter27h,
    mhpmcounter28h,
    mhpmcounter29h,
    mhpmcounter30h,
    mhpmcounter31h,

    mcountinhibit = 0x320,
    mcyclecfg,
    minstretcfg,
    mhpmevent3,
    mhpmevent4,
    mhpmevent5,
    mhpmevent6,
    mhpmevent7,
    mhpmevent8,
    mhpmevent9,
    mhpmevent10,
    mhpmevent11,
    mhpmevent12,
    mhpmevent13,
    mhpmevent14,
    mhpmevent15,
    mhpmevent16,
    mhpmevent17,
    mhpmevent18,
    mhpmevent19,
    mhpmevent20,
    mhpmevent21,
    mhpmevent22,
    mhpmevent23,
    mhpmevent24,
    mhpmevent25,
    mhpmevent26,
    mhpmevent27,
    mhpmevent28,
    mhpmevent29,
    mhpmevent30,
    mhpmevent31,
    mcyclecfgh = 0x721,
    minstretcfgh,
    mhpmevent3h,
    mhpmevent4h,
    mhpmevent5h,
    mhpmevent6h,
    mhpmevent7h,
    mhpmevent8h,
    mhpmevent9h,
    mhpmevent10h,
    mhpmevent11h,
    mhpmevent12h,
    mhpmevent13h,
    mhpmevent14h,
    mhpmevent15h,
    mhpmevent16h,
    mhpmevent17h,
    mhpmevent18h,
    mhpmevent19h,
    mhpmevent20h,
    mhpmevent21h,
    mhpmevent22h,
    mhpmevent23h,
    mhpmevent24h,
    mhpmevent25h,
    mhpmevent26h,
    mhpmevent27h,
    mhpmevent28h,
    mhpmevent29h,
    mhpmevent30h,
    mhpmevent31h,
    _,
};

pub const CsrPrivs = a: {
    @setEvalBranchQuota(10_000);
    const map = std.EnumMap(CsrNumber, CsrPriv).init(.{
        .cycle = CsrPriv{ .priv = .User },
        .time = CsrPriv{ .priv = .User },
        .instret = CsrPriv{ .priv = .User },
        .hpmcounter3 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter4 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter5 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter6 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter7 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter8 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter9 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter10 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter11 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter12 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter13 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter14 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter15 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter16 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter17 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter18 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter19 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter20 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter21 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter22 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter23 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter24 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter25 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter26 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter27 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter28 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter29 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter30 = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter31 = CsrPriv{ .priv = .User, .zero = true },
        .cycleh = CsrPriv{ .priv = .User },
        .timeh = CsrPriv{ .priv = .User, .zero = true },
        .instreth = CsrPriv{ .priv = .User },
        .hpmcounter3h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter4h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter5h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter6h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter7h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter8h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter9h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter10h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter11h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter12h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter13h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter14h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter15h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter16h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter17h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter18h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter19h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter20h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter21h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter22h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter23h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter24h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter25h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter26h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter27h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter28h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter29h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter30h = CsrPriv{ .priv = .User, .zero = true },
        .hpmcounter31h = CsrPriv{ .priv = .User, .zero = true },

        .mvendorid = CsrPriv{ .priv = .Machine, .zero = true },
        .marchid = CsrPriv{ .priv = .Machine, .zero = true },
        .mimpid = CsrPriv{ .priv = .Machine, .zero = true },
        .mhartid = CsrPriv{ .priv = .Machine, .zero = true },
        .mconfigptr = CsrPriv{ .priv = .Machine, .zero = true },

        .mstatus = CsrPriv{ .priv = .Machine, .write = true },
        .misa = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        // No interrupts defined for now
        .mie = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mtvec = CsrPriv{ .priv = .Machine, .write = true },
        .mcounteren = CsrPriv{ .priv = .Machine, .write = true },
        .mstatush = CsrPriv{ .priv = .Machine, .write = true },

        .mscratch = CsrPriv{ .priv = .Machine, .write = true },
        .mepc = CsrPriv{ .priv = .Machine, .write = true },
        .mcause = CsrPriv{ .priv = .Machine, .write = true },
        .mtval = CsrPriv{ .priv = .Machine, .write = true },
        // No interrupts defined for now
        .mip = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mtinst = CsrPriv{ .priv = .Machine, .write = true, .zero = true },

        .menvcfg = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .menvcfgh = CsrPriv{ .priv = .Machine, .write = true, .zero = true },

        .mcycle = CsrPriv{ .priv = .Machine, .write = true },
        .minstret = CsrPriv{ .priv = .Machine, .write = true },
        .mhpmcounter3 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter4 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter5 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter6 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter7 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter8 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter9 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter10 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter11 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter12 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter13 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter14 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter15 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter16 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter17 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter18 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter19 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter20 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter21 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter22 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter23 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter24 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter25 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter26 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter27 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter28 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter29 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter30 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter31 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mcycleh = CsrPriv{ .priv = .Machine, .write = true },
        .minstreth = CsrPriv{ .priv = .Machine, .write = true },
        .mhpmcounter3h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter4h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter5h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter6h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter7h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter8h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter9h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter10h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter11h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter12h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter13h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter14h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter15h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter16h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter17h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter18h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter19h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter20h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter21h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter22h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter23h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter24h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter25h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter26h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter27h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter28h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter29h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter30h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmcounter31h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },

        .mcountinhibit = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mcyclecfg = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .minstretcfg = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent3 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent4 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent5 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent6 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent7 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent8 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent9 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent10 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent11 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent12 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent13 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent14 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent15 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent16 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent17 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent18 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent19 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent20 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent21 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent22 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent23 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent24 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent25 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent26 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent27 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent28 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent29 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent30 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent31 = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mcyclecfgh = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .minstretcfgh = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent3h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent4h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent5h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent6h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent7h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent8h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent9h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent10h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent11h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent12h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent13h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent14h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent15h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent16h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent17h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent18h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent19h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent20h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent21h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent22h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent23h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent24h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent25h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent26h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent27h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent28h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent29h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent30h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
        .mhpmevent31h = CsrPriv{ .priv = .Machine, .write = true, .zero = true },
    });
    break :a map;
};

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

pub const Exception = error{
    IllegalInstruction,
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
    CustomHaltAddressWritten = 63, // If an address designated a halt address is stored to, raise this exception
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
        const RoZero = enum { mode };
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
        ret |= @truncate(0xFFFF_FFFF << 12);
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
