//! A Hart is to Risc-V what a Core is to x86. It is a distinct processing unit.

const std = @import("std");
const Bus = @import("bus.zig").Bus;

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

/// Lookup table to determine how to interpret/assemble each instruction
const instructions = .{
    // TODO
    .add = .{},
};

/// Keeps the result of the last Fetch operation
const FetchBuffer = struct {
    instruction: u32,
};

/// Keeps the result of the last Decode operation
const DecodeBuffer = struct {
    instruction: u32,
};

/// Keeps the result of the last Read Registers operation
const ReadRegistersBuffer = struct {
    instruction: u32,
};

/// Keeps the result of the last Execute operation
const ExecuteBuffer = struct {
    instruction: u32,
};

/// Keeps the result of the last Memory Access operation
const MemoryAccessBuffer = struct {
    instruction: u32,
};

// Writeback does not need to pass information to any other stage, so it doesn't get a buffer

pub const Hart = struct {
    registers: [32]u32 = [_]u32{0} ** 32,
    pc: u32 = 0,

    fetch_buf: FetchBuffer,
    decode_buf: DecodeBuffer,
    read_registers_buf: ReadRegistersBuffer,
    execute_buf: ExecuteBuffer,
    memory_access_buf: MemoryAccessBuffer,

    bus: Bus,
};
