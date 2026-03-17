//! The memory operations operate on the bus, which addresses one unified address space including main memory,
//! I/O mapped devices and the boot and program ROMs
//!
//! This emulated CPU is little-endian, as most real processors are, so the least significant bytes are stored in lower
//! addresses.

// Memory map
//
//              |---------------------------|   Access (Read/Write/Execute = rwx)
// 0xBFFF FFFF  | Dynamic RAM (1GB)         |   rwx
// 0x8000 0000  | Program RAM               |
//              |---------------------------|
// 0x1000 1FFF  | Boot ROM (4KB)            |   r-x
// 0x1000 0000  |                           |
//              |---------------------------|
// 0x0FFF FFFF  | Memory-mapped I/O (256MB) |   rw-
// 0x0000 0000  |---------------------------|
//
// This memory map is left with some gaps, leaving space to expand regions without needing to split them up.
// The emulator should be built so that changing these sizes is simple and easy, and the eventual Factorio
// port may take this exact same map or modify it according to constraints that could arise.
//
// I/O devices
// Timers: registers that count the number ticks passing in real time (60 ticks per second). They could also count
//          in discrete intervals amounting to the number of ticks per clock cycle.
//      - A system timer, known as CLInt or mtime
//
// Graphics? A framebuffer that may be manipulated by the CPU
// A coprocessor? A discrete graphics/picture processor which does more complex operations on the framebuffer like
// drawing lines or copying sprites.

const std = @import("std");

const Bus = @import("Bus.zig");
const MmioDevice = @import("MmioDevice.zig");
const MemoryError = Bus.MemoryError;
const AccessControl = Bus.AccessControl;
const Width = Bus.Width;
const CharDev = @import("CharDev.zig");
const CLInt = @import("CLInt.zig");

pub const RamStart: u32 = 0x8000_0000;
// 1GB of main memory
pub const RamSize: u32 = 0x4000_0000;

pub const MmioStart: u32 = 0x0000_0000;
// 256MB of memory mapped I/O
pub const MmioSize: u32 = 0x1000_0000;

pub const BootRomStart: u32 = 0x1000_0000;
// 4KB of boot ROM
pub const BootRomSize: u32 = 0x1000;

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
        .name = "Memory mapped I/O",
        .access = AccessControl{
            .read = true,
            .write = true,
            .io = true,
        },
        .start = MmioStart,
        .size = MmioSize,
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

const DeviceAddresses = .{
    .clint = &[_]u32{ 0x100, 0x104, 0x108, 0x10c },
    .chardev = &[_]u32{0x200},
};

pub const StandardBus = struct {
    boot_rom: []u8 = &.{},
    /// Hash map of 4K blocks of memory, allocated only when needed
    ram: std.AutoArrayHashMap(u32, []u8) = undefined,

    allocator: std.mem.Allocator = undefined,

    start: u32 = BootRomStart,

    chardev: CharDev = undefined,
    clint: CLInt = undefined,

    devices: std.ArrayList(MmioDevice) = std.ArrayList(MmioDevice).empty,

    pub fn init(self: *@This(), allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.boot_rom = try self.allocator.alloc(u8, BootRomSize);
        self.ram = std.AutoArrayHashMap(u32, []u8).init(allocator);
        self.start = BootRomStart;

        self.devices = std.ArrayList(MmioDevice).empty;
        self.chardev.init(null, DeviceAddresses.chardev);
        try self.devices.append(self.allocator, self.chardev.interface());
        self.clint.init(DeviceAddresses.clint);
        try self.devices.append(self.allocator, self.clint.interface());
    }

    pub fn deinit(self: *@This()) void {
        self.devices.deinit(self.allocator);
        for (self.ram.values()) |block| {
            self.allocator.free(block);
        }
        self.ram.deinit();
        self.allocator.free(self.boot_rom);
    }

    pub fn interface(self: *@This()) Bus {
        return Bus.implBy(self);
    }

    pub fn setCharDevWriter(self: *@This(), writer: *std.io.Writer) void {
        self.chardev.init(writer, DeviceAddresses.chardev);
    }

    pub fn stepDevices(self: *@This()) void {
        for (self.devices.items) |dev| {
            dev.step();
        }
    }

    pub fn getTimeAddrs(self: *@This()) ?[4]u32 {
        return self.clint.addresses;
    }

    /// Set a byte in RAM. If the 4K block the address falls into is already allocated, simply sets the
    /// byte at the requested address. If not, the block is first allocated.
    /// If allocation fails, returns a MemoryError.HardwareError, which should halt the emulator
    fn setbRam(self: *@This(), addr: u32, byte: u8) MemoryError!void {
        const address = addr - RamStart;
        if (self.ram.get(address >> 12)) |block| {
            block[address & ((1 << 12) - 1)] = byte;
        } else {
            var block = self.allocator.alloc(u8, 1 << 12) catch {
                return MemoryError.HardwareError;
            };
            block[address & ((1 << 12) - 1)] = byte;
            self.ram.put(address >> 12, block) catch {
                self.allocator.free(block);
                return MemoryError.HardwareError;
            };
        }
    }

    /// Set a single byte.
    /// Illegal access will fail silently.
    /// Does not check access control.
    /// If allocation fails, returns a MemoryError.HardwareError, which should halt the emulator
    fn setb(self: *@This(), addr: u32, byte: u8) MemoryError!void {
        if (addr >= RamStart and addr < RamStart + RamSize) {
            try self.setbRam(addr, byte);
        } else if (addr >= BootRomStart and addr < BootRomStart + BootRomSize) {
            self.boot_rom[addr - BootRomStart] = byte;
        }
        // else invalid address
        return;
    }

    /// Set the memory at the address to the value, truncated to width bytes.
    /// The maximum width supported is 4, with the minimum being 1.
    /// Illegal access or illegal width will fail silently.
    /// If allocation fails, returns a MemoryError.HardwareError, which should halt the emulator
    ///
    /// For access from an instruction, use the store method instead.
    /// Writing to ROM is perfectly fine in this method, as it is not meant for emulator use.
    pub fn set(self: *@This(), addr: u32, value: u32, width: Width) MemoryError!void {
        var bytes_buf: [4]u8 = .{ 0, 0, 0, 0 };
        var bytes: []u8 = undefined;

        if (addr >= MmioStart and addr < MmioStart + MmioSize) {
            self.store(addr, value, width) catch {};
            return;
        }

        switch (width) {
            .byte => {
                bytes_buf[0] = @truncate(value);
            },
            .halfword => {
                bytes_buf[0] = @truncate(value);
                bytes_buf[1] = @truncate(value >> 8);
            },
            .word => {
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
        bytes = bytes_buf[0..@intFromEnum(width)];

        for (bytes, 0..) |b, i| {
            try self.setb(addr +% @as(u32, @intCast(i)), b);
        }
    }

    /// Called by the CPU when setting a value at a memory address.
    /// Applies some restrictions to what memory ranges can be written to, and may fail depending on it.
    pub fn store(self: *@This(), addr: u32, value: u32, width: Width) MemoryError!void {
        // setb does not check access control, we need to do that here.
        // If a store for any address outside the allowed ranges is requested, return with a StoreAccessFault
        inline for (@typeInfo(@TypeOf(MemoryMap)).@"struct".fields) |field| {
            const range = @field(MemoryMap, field.name);

            if (addr >= range.start and addr < range.start + range.size and range.access.write) {
                if (range.access.io) {
                    for (self.devices.items) |dev| {
                        if (std.mem.indexOfScalar(u32, dev.addresses, addr & 0xFFFF_FFFC)) |_| {
                            try dev.store(addr, value, width);
                            return;
                        }
                    }
                } else {
                    for (0..@intFromEnum(width)) |i| {
                        try self.setb(addr +% @as(u32, @intCast(i)), @truncate(value >> @intCast(8 * i)));
                    }
                }
                return;
            }
        }
        return MemoryError.StoreAccessFault;
    }

    /// Get a byte from RAM. If the 4K block the address falls into is already allocated, returns the byte at
    /// that address. If not, returns the normal Zig undefined value: 0xAA.
    fn getbRam(self: *@This(), addr: u32) u8 {
        const address = addr - RamStart;
        if (self.ram.get(address >> 12)) |block| {
            return block[address & ((1 << 12) - 1)];
        } else {
            return 0xAA;
        }
    }

    /// Get a single byte.
    /// Illegal access will fail silently and return 0.
    /// Does not check access control.
    fn getb(self: *@This(), addr: u32) u8 {
        if (addr >= RamStart and addr < RamStart + RamSize) {
            return self.getbRam(addr);
        } else if (addr >= BootRomStart and addr < BootRomStart + BootRomSize) {
            return self.boot_rom[addr - BootRomStart];
        }
        // else invalid address
        return 0;
    }

    /// Get the memory at the address with width bytes.
    /// The maximum width supported is 4, with the minimum being 1.
    /// Illegal access will fail silently and return 0 for the affected bytes, no traps are set using this
    /// method.
    /// The returned value is 32 bits wide, filled with 0s if the requested width was less than 4.
    ///
    /// For access from an instruction, use the load method instead.
    /// Reading from restricted memory is perfectly fine in this method, as it is not meant for emulator use.
    pub fn get(self: *@This(), addr: u32, width: Width) u32 {
        var value: u32 = 0;

        if (addr >= MmioStart and addr < MmioStart + MmioSize) {
            value = self.load(addr, width) catch 0;
            return value;
        }

        for (0..@intFromEnum(width)) |i| {
            value |= @as(u32, self.getb(addr +% @as(u32, @truncate(i)))) << (8 * @as(u5, @truncate(i)));
        }

        return value;
    }

    /// Called by the CPU when getting a value at a memory address.
    /// Applies some restrictions to what memory ranges can be read from, and may fail depending on it.
    pub fn load(self: *@This(), addr: u32, width: Width) MemoryError!u32 {
        var ret: u32 = 0;

        // getb does not check access control, we need to do that here.
        // If a load for any address outside the allowed ranges is requested, return with a LaodAccessFault
        inline for (@typeInfo(@TypeOf(MemoryMap)).@"struct".fields) |field| {
            const range = @field(MemoryMap, field.name);

            if (addr >= range.start and addr < range.start + range.size and range.access.read) {
                if (range.access.io) {
                    for (self.devices.items) |dev| {
                        if (std.mem.indexOfScalar(u32, dev.addresses, addr & 0xFFFF_FFFC)) |_| {
                            return dev.load(addr, width);
                        }
                    }
                } else {
                    for (0..@intFromEnum(width)) |i| {
                        ret |= @as(u32, self.getb(addr +% @as(u32, @truncate(i)))) << (8 * @as(u5, @truncate(i)));
                    }
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
                return self.get(addr, .word);
            }
        }

        return MemoryError.InstructionAccessFault;
    }

    /// Get PC reset value
    pub fn getStart(self: @This()) u32 {
        return self.start;
    }
};
