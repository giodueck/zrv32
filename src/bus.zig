//! The memory operations operate on the bus, which addresses one unified address space including main memory,
//! I/O mapped devices and the boot and program ROMs
//!
//! This emulated CPU is little-endian, as most real processors are, so the least significant bytes are stored in lower
//! addresses.

// Memory map
//
//              |---------------------------|   Access (Read/Write/Execute = rwx)
//              | Unused                    |   r--
//              |---------------------------|
// 0x0004 FFFF  | Dynamic RAM (64KB)        |   rw-
// 0x0004 0000  |                           |
//              |---------------------------|
//              | Unused                    |   r--
//              |---------------------------|
// 0x0001 FFFF  | Mapped I/O (64KB)         |   rw-
// 0x0001 0000  |                           |
//              |---------------------------|
//              | Unused                    |   r--
//              |---------------------------|
// 0x0000 7FFF  | Program ROM (24KB)        |   --x
// 0x0000 1000  |                           |
//              |---------------------------|
// 0x0000 1FFF  | Boot ROM    (4KB)         |   --x
// 0x0000 1000  | Boot address: 0x0000 1000 |
// 0x0000 0000  |---------------------------|
//
// This is a Harvard architecture, meaning that program and data memory is separate. Thus, executable memory
// is not readable or writable, and readable or writable memory is not executable.
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

pub const RamStart: u32 = 0x0004_0000;
// 64KB of main memory
pub const RamSize: u32 = 0x1_0000;

pub const ProgramRomStart: u32 = 0x0000_2000;
// 24KB of program ROM
pub const ProgramRomSize: u32 = 0x6000;

pub const BootRomStart: u32 = 0x0000_1000;
// 4KB of boot ROM
pub const BootRomSize: u32 = 0x1000;

const AccessControl = struct {
    read: bool = false,
    write: bool = false,
    execute: bool = false,
};

pub const MemoryError = error{
    IllegalInstruction,
    InstructionAccessFault,
    InstructionAddressMisaligned,
    LoadAccessFault,
    StoreAccessFault,
    // Load/StoreAccessMisaligned could potentially also be here, but we can support those easily
};

const MemoryMap = .{
    .{
        .name = "Boot ROM",
        .access = AccessControl{
            .execute = true,
            .read = true,
        },
        .start = BootRomStart,
        .size = BootRomSize,
    },
    .{
        .name = "Program ROM",
        .access = AccessControl{
            .execute = true,
            .read = true,
        },
        .start = ProgramRomStart,
        .size = ProgramRomSize,
    },
    .{
        .name = "Dynamic RAM",
        .access = AccessControl{
            .read = true,
            .write = true,
        },
        .start = RamStart,
        .size = RamSize,
    },
};

pub const Bus = struct {
    boot_rom: []u8 = undefined,
    program_rom: []u8 = undefined,
    ram: []u8 = undefined,

    allocator: std.mem.Allocator = undefined,

    ram_start: u32 = RamStart,
    ram_size: u32 = RamSize,
    program_rom_start: u32 = ProgramRomStart,
    program_rom_size: u32 = ProgramRomSize,
    boot_rom_start: u32 = BootRomStart,
    boot_rom_size: u32 = BootRomSize,

    pub fn init(self: *@This(), allocator: std.mem.Allocator) !void {
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

    /// Set a single byte.
    /// Illegal access will fail silently.
    /// Does not check access control.
    fn setb(self: *@This(), addr: u32, byte: u8) void {
        if (addr >= RamStart and addr < RamStart + RamSize) {
            self.ram[addr - RamStart] = byte;
        } else if (addr >= ProgramRomStart and addr < ProgramRomStart + ProgramRomSize) {
            self.ram[addr - ProgramRomStart] = byte;
        } else if (addr >= BootRomStart and addr < BootRomStart + BootRomSize) {
            self.ram[addr - BootRomStart] = byte;
        }
        // else invalid address
        return;
    }

    /// Set the memory at the address to the value, truncated to width bytes.
    /// The maximum width supported is 4, with the minimum being 1.
    /// Illegal access or illegal width will fail silently, no traps are set using this method.
    ///
    /// For access from an instruction, use the store method instead.
    /// Writing to ROM is perfectly fine in this method, as it is not meant for emulator use.
    pub fn set(self: *@This(), addr: u32, value: u32, width: u3) void {
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
            self.setb(addr +% @as(u32, @intCast(i)), b);
        }
    }

    /// Called by the CPU when setting a value at a memory address.
    /// Applies some restrictions to what memory ranges can be written to, and may fail depending on it.
    pub fn store(self: *@This(), addr: u32, value: u32, width: u32) MemoryError!void {
        if (width > 4 or width == 3) return MemoryError.IllegalInstruction;

        // setb does not check access control, we need to do that here.
        // If a store for any address outside the allowed ranges is requested, return with a StoreAccessFault
        inline for (@typeInfo(@TypeOf(MemoryMap)).@"struct".fields) |field| {
            const range = @field(MemoryMap, field.name);

            if (addr >= range.start and addr < range.start + range.size and range.access.write) {
                for (0..width) |i| {
                    self.setb(addr +% @as(u32, @intCast(i)), @truncate(value >> @intCast(8 * i)));
                }
                return;
            }
        }
        return MemoryError.StoreAccessFault;
    }

    /// Get a single byte.
    /// Illegal access will fail silently and return 0.
    /// Does not check access control.
    fn getb(self: @This(), addr: u32) u8 {
        if (addr >= RamStart and addr < RamStart + RamSize) {
            return self.ram[addr - RamStart];
        } else if (addr >= ProgramRomStart and addr < ProgramRomStart + ProgramRomSize) {
            return self.ram[addr - ProgramRomStart];
        } else if (addr >= BootRomStart and addr < BootRomStart + BootRomSize) {
            return self.ram[addr - BootRomStart];
        }
        // else invalid address
        return 0;
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
            value |= @as(u32, self.getb(addr +% @as(u32, @truncate(i)))) << (8 * @as(u5, @truncate(i)));
        }

        return value;
    }

    /// Called by the CPU when getting a value at a memory address.
    /// Applies some restrictions to what memory ranges can be read from, and may fail depending on it.
    pub fn load(self: *@This(), addr: u32, width: u32) MemoryError!u32 {
        if (width > 4 or width == 3) return MemoryError.IllegalInstruction;

        var ret: u32 = 0;

        // getb does not check access control, we need to do that here.
        // If a load for any address outside the allowed ranges is requested, return with a LaodAccessFault
        inline for (@typeInfo(@TypeOf(MemoryMap)).@"struct".fields) |field| {
            const range = @field(MemoryMap, field.name);

            if (addr >= range.start and addr < range.start + range.size and range.access.read) {
                for (0..width) |i| {
                    ret |= @as(u32, self.getb(addr +% @as(u32, @truncate(i)))) << (8 * @as(u5, @truncate(i)));
                }
                return ret;
            }
        }
        return MemoryError.LoadAccessFault;
    }

    /// Called by the CPU when getting a value at a memory address for execution.
    /// Applies some restrictions to what memory ranges can be executed from, and may fail depending on it.
    pub fn fetch(self: *@This(), addr: u32) MemoryError!u32 {
        if (addr & 3 != 0) return MemoryError.InstructionAddressMisaligned;

        // get does not check access control, we need to do that here.
        // If a start address is allowed and aligned, all bytes should generally be allowed to be fetched.
        inline for (@typeInfo(@TypeOf(MemoryMap)).@"struct".fields) |field| {
            const range = @field(MemoryMap, field.name);

            if (addr >= range.start and addr < range.start + range.size and range.access.execute) {
                return self.get(addr, 4);
            }
        }

        return MemoryError.InstructionAccessFault;
    }
};
