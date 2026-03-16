const std = @import("std");

const Bus = @import("Bus.zig");
const MemoryError = Bus.MemoryError;
const AccessControl = Bus.AccessControl;
const chardev = @import("chardev.zig");

pub const TestRamStart: u32 = 0x8000_0000;
// 1MB of memory for running tests
pub const TestRamSize: u32 = 0x10_0000;

pub const MmioStart: u32 = 0x0001_0000;
// 64KB of memory mapped I/O
pub const MmioSize: u32 = 0x1_0000;

const MemoryMap = .{
    .{
        .name = "Test RAM",
        .access = AccessControl{
            .execute = true,
            .read = true,
            .write = true,
        },
        .start = TestRamStart,
        .size = TestRamSize,
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
};

const Devices = enum(u32) {
    CharDev = 0x1_0000,
    _,
};

pub const TestBus = struct {
    ram: []u8 = &.{},

    allocator: std.mem.Allocator = undefined,

    start: u32 = TestRamStart,

    /// This address is used by riscv-tests tests to signal end of the test
    halt_address: u32 = 0x0,

    chardev: chardev.CharDev = undefined,

    pub fn init(self: *@This(), allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.ram = try self.allocator.alloc(u8, TestRamSize);
        self.chardev.init(null);
        self.start = TestRamStart;
    }

    pub fn deinit(self: *@This()) void {
        self.allocator.free(self.ram);
    }

    pub fn interface(self: *@This()) Bus {
        return Bus.implBy(self);
    }

    pub fn setCharDevWriter(self: *@This(), writer: *std.io.Writer) void {
        self.chardev.init(writer);
    }

    /// Set a single byte.
    /// Illegal access will fail silently.
    /// Does not check access control.
    fn setb(self: *@This(), addr: u32, byte: u8) void {
        if (addr >= TestRamStart and addr < TestRamStart + TestRamSize) {
            self.ram[addr - TestRamStart] = byte;
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

        if (addr == self.halt_address) return MemoryError.HaltAddressWritten;

        // setb does not check access control, we need to do that here.
        // If a store for any address outside the allowed ranges is requested, return with a StoreAccessFault
        inline for (@typeInfo(@TypeOf(MemoryMap)).@"struct".fields) |field| {
            const range = @field(MemoryMap, field.name);

            if (addr >= range.start and addr < range.start + range.size and range.access.write) {
                if (range.access.io) {
                    switch (@as(Devices, @enumFromInt(addr))) {
                        _ => {
                            return MemoryError.StoreAccessFault;
                        },
                        .CharDev => {
                            self.chardev.store(addr, value, width);
                        },
                    }
                } else {
                    for (0..width) |i| {
                        self.setb(addr +% @as(u32, @intCast(i)), @truncate(value >> @intCast(8 * i)));
                    }
                }
                return;
            }
        }
        return MemoryError.StoreAccessFault;
    }

    /// Get a single byte.
    /// Illegal access will fail silently and return 0.
    /// Does not check access control.
    fn getb(self: *@This(), addr: u32) u8 {
        if (addr >= TestRamStart and addr < TestRamStart + TestRamSize) {
            return self.ram[addr - TestRamStart];
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
    pub fn get(self: *@This(), addr: u32, width: u3) u32 {
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
                if (range.access.io) {
                    switch (@as(Devices, @enumFromInt(addr))) {
                        _ => {
                            return MemoryError.LoadAccessFault;
                        },
                        .CharDev => {
                            return self.chardev.load(addr, width);
                        },
                    }
                } else {
                    for (0..width) |i| {
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
                return self.get(addr, 4);
            }
        }

        return MemoryError.InstructionAccessFault;
    }

    /// Get PC reset value
    pub fn getStart(self: @This()) u32 {
        return self.start;
    }
};
