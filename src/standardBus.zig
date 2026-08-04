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

const common = @import("common.zig");

const Bus = @import("Bus.zig");
const MmioDevice = @import("MmioDevice.zig");
const MemoryError = Bus.MemoryError;
const AccessControl = Bus.AccessControl;
const Width = Bus.Width;
const OutputCharDev = @import("OutputCharDev.zig");
const InputCharDev = @import("InputCharDev.zig");
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
            .execute = true,
        },
        .start = RamStart,
        .size = RamSize,
    },
};

const DeviceAddresses = .{
    .clint = &[_]u32{ 0x100, 0x104, 0x108, 0x10c },
    .outchardev = &[_]u32{0x200},
    .inchardev = &[_]u32{0x204},
};

pub const StandardBus = struct {
    boot_rom: []u8 = &.{},
    /// Sparse array with pages of 4K bytes, allocated only when needed
    ram: common.SparseArray(u30, u8, u12) = undefined,

    gpa: std.mem.Allocator = undefined,

    start: u32 = BootRomStart,

    clint: CLInt = undefined,
    outchardev: OutputCharDev = undefined,
    inchardev: InputCharDev = undefined,

    devices: std.ArrayList(MmioDevice) = std.ArrayList(MmioDevice).empty,

    pub fn init(self: *@This(), allocator: std.mem.Allocator) !void {
        self.gpa = allocator;
        self.boot_rom = try self.gpa.alloc(u8, BootRomSize);
        @memset(self.boot_rom, 0);
        self.ram = try common.SparseArray(u30, u8, u12).init(self.gpa);
        self.start = BootRomStart;

        self.devices = std.ArrayList(MmioDevice).empty;
        self.clint.init(DeviceAddresses.clint);
        try self.devices.append(self.gpa, self.clint.interface());

        self.outchardev.init(null, null, DeviceAddresses.outchardev);
        try self.devices.append(self.gpa, self.outchardev.interface());
        self.inchardev.init(null, DeviceAddresses.inchardev);
        try self.devices.append(self.gpa, self.inchardev.interface());
    }

    pub fn deinit(self: *@This()) void {
        self.devices.deinit(self.gpa);
        self.ram.deinit(self.gpa);
        self.gpa.free(self.boot_rom);
    }

    pub fn interface(self: *@This()) Bus {
        return Bus.implBy(self);
    }

    pub fn setOutputCharDevWriter(self: *@This(), io: std.Io, writer: *std.Io.Writer) void {
        self.outchardev.init(io, writer, DeviceAddresses.outchardev);
    }

    pub fn setInputCharDevReader(self: *@This(), reader: *std.Io.Reader) void {
        self.inchardev.init(reader, DeviceAddresses.inchardev);
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
        self.ram.set(self.gpa, @truncate(address), byte) catch {
            return MemoryError.HardwareError;
        };
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
                        for (dev.addresses) |a| {
                            if (a == addr & 0xFFFF_FFFC) {
                                try dev.store(addr, value, width);
                                return;
                            }
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
    /// that address. If not, returns 0.
    fn getbRam(self: *@This(), addr: u32) u8 {
        const address = addr - RamStart;
        return self.ram.get(@truncate(address)) orelse 0;
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
                        for (dev.addresses) |a| {
                            if (a == addr & 0xFFFF_FFFC) {
                                return dev.load(addr, width);
                            }
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

    pub fn getSlice(self: *@This(), allocator: std.mem.Allocator, start_addr: u32, len: u32) error{OutOfMemory}![]?u8 {
        var slice = try allocator.alloc(?u8, len);

        // First access all misaligned addresses, if any, at the start to avoid misaligned errors
        const mastart = start_addr & 3;
        for (0..mastart) |i| {
            const addr = start_addr + @as(u32, @intCast(i));
            inline for (@typeInfo(@TypeOf(MemoryMap)).@"struct".fields) |field| {
                const range = @field(MemoryMap, field.name);

                if (addr >= range.start and addr < range.start + range.size and range.access.read) {
                    // Don't want to deal with misaligned and non-word device memory accesses
                    if (!range.access.io) {
                        slice[i] = self.getb(addr +% @as(u32, @truncate(i)));
                    }
                    break;
                }
            }
            slice[i] = null;
        }

        // Then access all aligned words in the middle
        const alignedlen = (len - mastart) & 0xFFFF_FFFC;

        var i: u32 = mastart;
        while (i < alignedlen) : (i += 4) {
            const addr = start_addr + mastart + @as(u32, @intCast(i));
            var val: ?u32 = null;
            inline_for: inline for (@typeInfo(@TypeOf(MemoryMap)).@"struct".fields) |field| {
                const range = @field(MemoryMap, field.name);

                if (addr >= range.start and addr < range.start + range.size and range.access.read) {
                    if (range.access.io) {
                        for (self.devices.items) |dev| {
                            for (dev.addresses) |a| {
                                if (a == addr & 0xFFFF_FFFC) {
                                    val = dev.load(addr, .word) catch null;
                                    break :inline_for;
                                }
                            }
                        }
                    } else {
                        val = 0;
                        for (0..4) |j| {
                            var b: ?u8 = null;
                            if (addr >= RamStart and addr < RamStart + RamSize) {
                                b = self.ram.get(@truncate(addr - RamStart + j));
                            } else if (addr >= BootRomStart and addr < BootRomStart + BootRomSize) {
                                b = self.boot_rom[addr - BootRomStart + j];
                            } else {
                                b = null;
                            }

                            if (b == null) {
                                val = null;
                                break :inline_for;
                            }

                            val.? |= @as(u32, b.?) << (8 * @as(u5, @truncate(j)));
                        }
                        break :inline_for;
                    }
                }
            }
            if (val) |word| {
                slice[i] = @truncate(word);
                slice[i + 1] = @truncate(word >> 8);
                slice[i + 2] = @truncate(word >> 16);
                slice[i + 3] = @truncate(word >> 24);
            } else {
                slice[i] = null;
                slice[i + 1] = null;
                slice[i + 2] = null;
                slice[i + 3] = null;
            }
        }

        return slice;
    }

    // Then skip all trailing misaligned addresses
};
