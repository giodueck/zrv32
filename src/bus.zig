//! The memory operations operate on the bus, which addresses one unified address space including main memory,
//! I/O mapped devices and the boot and program ROMs
//!
//! This emulated CPU is little-endian, as most real processors are, so the least significant bytes are stored in lower
//! addresses.

// Memory map
//
//              |---------------------------|
//              | Unused                    |
//              |---------------------------|
// 0x0004 FFFF  | Dynamic RAM (64KB)        |
// 0x0004 0000  |                           |
//              |---------------------------|
//              | Unused                    |
//              |---------------------------|
// 0x0001 FFFF  | Mapped I/O (64KB)         |
// 0x0001 0000  |                           |
//              |---------------------------|
//              | Unused                    |
//              |---------------------------|
// 0x0000 7FFF  | Program ROM (24KB)        |
// 0x0000 1000  |                           |
//              |---------------------------|
// 0x0000 1FFF  | Boot ROM    (4KB)         |
// 0x0000 1000  | Boot address: 0x0000 1000 |
// 0x0000 0000  |---------------------------|
//
// This memory map is left with some gaps, leaving space to expand regions without needing to split them up.
// The emulator should be built so that changing these sizes is simple and easy, and the eventual Factorio
// port may take this exact same map or modify it according to constraints that could arise.
//
// I/O devices
// Timers: registers that count the number ticks passing in real time (60 ticks per second). They could also count
//          in discrete intervals amounting to the number of ticks per clock cycle.
//      - A system timer, reset only when the entire system is reset.
//      - A user timer, reset when the user writes to it.
//
// Graphics? A framebuffer that may be manipulated by the CPU
// A coprocessor? A discrete graphics/picture processor which does more complex operations on the framebuffer like
// drawing lines or copying sprites.

const std = @import("std");

const RamStart = 0x0004_0000;
// 64KB of main memory
const RamSize = 0x1_0000;

const ProgramRomStart = 0x0000_2000;
// 24KB of program ROM
const ProgramRomSize = 0x6000;

const BootRomStart = 0x0000_1000;
// 4KB of boot ROM
const BootRomSize = 0x1000;

pub const Bus = struct {
    boot_rom: []u8 = undefined,
    program_rom: []u8 = undefined,
    ram: []u8 = undefined,

    allocator: std.mem.Allocator = undefined,

    pub fn init(self: @This(), allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.boot_rom = try self.allocator.alloc(u8, BootRomSize);
        self.program_rom = try self.allocator.alloc(u8, ProgramRomSize);
        self.ram = try self.allocator.alloc(u8, RamSize);
    }

    pub fn deinit(self: @This()) void {
        self.allocator.free(self.ram);
        self.allocator.free(self.program_rom);
        self.allocator.free(self.boot_rom);
    }

    /// Set a single byte
    fn setb(self: @This(), addr: u32, byte: u8) void {
        if (addr >= RamStart and addr < RamStart + RamSize) {
            self.ram[addr - RamStart] = byte;
        } else if (addr >= ProgramRomStart and addr < ProgramRomStart + ProgramRomSize) {
            self.ram[addr - ProgramRomStart] = byte;
        } else if (addr >= BootRomStart and addr < BootRomStart + BootRomSize) {
            self.ram[addr - BootRomStart] = byte;
        }
        // else invalid address
    }

    /// Set the memory at the address to the value, truncated to width bytes.
    /// The maximum width supported is 4, with the minimum being 1.
    /// Illegal access or illegal width will fail silently, no traps are set using this method.
    ///
    /// For access from an instruction, use the store method instead.
    /// Writing to ROM is perfectly fine in this method, as it is not meant for emulator use.
    pub fn set(self: @This(), addr: u32, value: u32, width: u3) void {
        var bytes_buf: [4]u8 = .{ 0, 0, 0, 0 };
        var bytes: []u8 = undefined;

        switch (width) {
            1 => {
                bytes_buf[0] = @truncate(value);
            },
            2 => {
                bytes_buf[0] = @truncate(value);
                bytes_buf[1] = @truncate(value >> 8);
            },
            3 => {
                bytes_buf[0] = @truncate(value);
                bytes_buf[1] = @truncate(value >> 8);
                bytes_buf[2] = @truncate(value >> 16);
            },
            4 => {
                bytes_buf[0] = @truncate(value);
                bytes_buf[1] = @truncate(value >> 8);
                bytes_buf[2] = @truncate(value >> 16);
                bytes_buf[3] = @truncate(value >> 24);
            },
            else => {
                // invalid width
                return;
            },
        }
        bytes = bytes_buf[0..width];

        for (bytes, 0..) |b, i| {
            self.setb(addr + i, b);
        }
    }

    /// Get a single byte
    fn getb(self: @This(), addr: u32) u8 {
        if (addr >= RamStart and addr < RamStart + RamSize) {
            return self.ram[addr - RamStart];
        } else if (addr >= ProgramRomStart and addr < ProgramRomStart + ProgramRomSize) {
            return self.ram[addr - ProgramRomStart];
        } else if (addr >= BootRomStart and addr < BootRomStart + BootRomSize) {
            return self.ram[addr - BootRomStart];
        }
        return 0;
        // else invalid address
    }

    /// Get the memory at the address with width bytes.
    /// The maximum width supported is 4, with the minimum being 1.
    /// Illegal width will fail silently and return 0.
    /// Illegal access will fail silently and return 0 for the affected bytes, no traps are set using this
    /// method.
    /// The returned value is 32 bits wide, filled with 0s if the requested width was less than 4.
    ///
    /// For access from an instruction, use the load method instead.
    /// Reading from restricted memory is perfectly fine in this method, as it is not meant for emulator use.
    pub fn get(self: @This(), addr: u32, width: u3) u32 {
        if (width > 4) return 0;

        var value: u32 = 0;
        for (0..width) |i| {
            value |= @as(u32, self.getb(addr + i)) << (8 * i);
        }

        return value;
    }
};
