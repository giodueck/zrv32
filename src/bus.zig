//! The memory operations operate on the bus, which addresses one unified address space including main memory,
//! I/O mapped devices and the boot and program ROMs
//!
//! This emulated CPU is little-endian, as most real processors are.

const std = @import("std");

const RamStart = 0x9000_0000;
// 2MB of main memory
const RamSize = 0x20_0000;

const ProgramRomStart = 0x8000_0000;
// 2MB of program ROM
const ProgramRomSize = 0x20_0000;

const BootRomStart = 0x0000_0000;
// 16KB of boot ROM
const BootRomSize = 0x4000;

// The space at 0x4000_0000 .. 0x7FFF_FFFF is dedicated to I/O mapped devices

pub const Bus = struct {
    boot_rom: []u8 = undefined,
    program_rom: []u8 = undefined,
    ram: []u8 = undefined,

    allocator: std.mem.Allocator = .{},

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
