const std = @import("std");

const Bus = @import("Bus.zig");
const MemoryError = Bus.MemoryError;
const AccessControl = Bus.AccessControl;
const Width = Bus.Width;

pub const TestRamStart: u32 = 0x8000_0000;
// 256MB of memory for running tests
pub const TestRamSize: u32 = 0x1000_0000;

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
};

pub const TestBus = struct {
    /// Hash map of 4K blocks of memory, allocated only when needed
    ram: std.array_hash_map.Auto(u32, []u8) = .empty,

    allocator: std.mem.Allocator = undefined,

    start: u32 = TestRamStart,

    /// This address is used by riscv-tests tests to signal end of the test
    halt_address: u32 = 0x0,

    pub fn init(self: *@This(), allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.ram = std.array_hash_map.Auto(u32, []u8).empty;
        self.start = TestRamStart;
    }

    pub fn deinit(self: *@This()) void {
        for (self.ram.values()) |block| {
            self.allocator.free(block);
        }
        self.ram.deinit(self.allocator);
    }

    pub fn interface(self: *@This()) Bus {
        return Bus.implBy(self);
    }

    /// Stub: unimplemented
    pub fn setOutputCharDevWriter(self: *@This(), io: std.Io, writer: *std.Io.Writer) void {
        _ = self;
        _ = io;
        _ = writer;
    }

    /// Stub: unimplemented
    pub fn setInputCharDevReader(self: *@This(), reader: *std.Io.Reader) void {
        _ = self;
        _ = reader;
    }

    pub fn stepDevices(self: *@This()) void {
        _ = self;
    }

    pub fn getTimeAddrs(self: *@This()) ?[4]u32 {
        _ = self;
        return null;
    }

    /// Set a byte in RAM. If the 4K block the address falls into is already allocated, simply sets the
    /// byte at the requested address. If not, the block is first allocated.
    /// If allocation fails, returns a MemoryError.HardwareError, which should halt the emulator
    fn setbRam(self: *@This(), addr: u32, byte: u8) MemoryError!void {
        const address = addr - TestRamStart;
        if (self.ram.get(address >> 12)) |block| {
            block[address & ((1 << 12) - 1)] = byte;
        } else {
            var block = self.allocator.alloc(u8, 1 << 12) catch {
                return MemoryError.HardwareError;
            };
            block[address & ((1 << 12) - 1)] = byte;
            self.ram.put(self.allocator, address >> 12, block) catch {
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
        if (addr >= TestRamStart and addr < TestRamStart + TestRamSize) {
            try self.setbRam(addr, byte);
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
        if (addr == self.halt_address) return MemoryError.HaltAddressWritten;

        // setb does not check access control, we need to do that here.
        // If a store for any address outside the allowed ranges is requested, return with a StoreAccessFault
        inline for (@typeInfo(@TypeOf(MemoryMap)).@"struct".fields) |field| {
            const range = @field(MemoryMap, field.name);

            if (addr >= range.start and addr < range.start + range.size and range.access.write) {
                for (0..@intFromEnum(width)) |i| {
                    try self.setb(addr +% @as(u32, @intCast(i)), @truncate(value >> @intCast(8 * i)));
                }
                return;
            }
        }
        return MemoryError.StoreAccessFault;
    }

    /// Get a byte from RAM. If the 4K block the address falls into is already allocated, returns the byte at
    /// that address. If not, returns the normal Zig undefined value: 0xAA.
    fn getbRam(self: *@This(), addr: u32) u8 {
        const address = addr - TestRamStart;
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
        if (addr >= TestRamStart and addr < TestRamStart + TestRamSize) {
            return self.getbRam(addr);
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
    pub fn get(self: *@This(), addr: u32, width: Width) u32 {
        var value: u32 = 0;
        for (0..@intFromEnum(width)) |i| {
            value |= @as(u32, self.getb(addr +% @as(u32, @truncate(i)))) << (8 * @as(u5, @truncate(i)));
        }

        return value;
    }

    /// Called by the CPU when getting a value at a memory address.
    /// Applies some restrictions to what memory ranges can be read from, and may fail depending on it.
    /// width is the width in bytes, being at most 4.
    pub fn load(self: *@This(), addr: u32, width: Width) MemoryError!u32 {
        var ret: u32 = 0;

        // getb does not check access control, we need to do that here.
        // If a load for any address outside the allowed ranges is requested, return with a LaodAccessFault
        inline for (@typeInfo(@TypeOf(MemoryMap)).@"struct".fields) |field| {
            const range = @field(MemoryMap, field.name);

            if (addr >= range.start and addr < range.start + range.size and range.access.read) {
                for (0..@intFromEnum(width)) |i| {
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
        _=self;_=start_addr;_=len;
        var ret = try allocator.alloc(?u8, 1);
        ret[0] = 0;
        return ret;
    }
};
