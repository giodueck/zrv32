const std = @import("std");
const common = @import("common.zig");
const MmioDevice = @import("MmioDevice.zig");
const Bus = @import("Bus.zig");
const MemoryError = Bus.MemoryError;
const Width = Bus.Width;

const InputCharDev = @This();

reader: ?*std.io.Reader = undefined,
addresses: [1]u32 = [1]u32{0},

pub fn init(self: *InputCharDev, reader: ?*std.io.Reader, addrs: []const u32) void {
    self.reader = reader;
    for (0..self.addresses.len, addrs) |i, addr| {
        self.addresses[i] = addr;
    }
}

pub fn interface(self: *InputCharDev) MmioDevice {
    return MmioDevice.implBy(self);
}

pub fn getAddresses(self: *InputCharDev) []u32 {
    return &self.addresses;
}

pub fn store(self: *InputCharDev, addr: u32, value: u32, width: Width) MemoryError!void {
    _ = self;
    _ = value;
    if (Bus.isMisaligned(addr, width)) return MemoryError.StoreAddressMisaligned;
}

/// Load the next item in the queue.
/// Normally, only single bytes are valid values.
/// If the buffer is empty or there is no reader set, this value will be 32 bits wide -1.
pub fn load(self: *InputCharDev, addr: u32, width: Width) MemoryError!u32 {
    std.debug.print("input load {x}: {x}\n", .{addr, self.reader.?.peekByte() catch @as(u8, 0xff)});
    if (Bus.isMisaligned(addr, width)) return MemoryError.LoadAddressMisaligned;
    if (self.reader) |reader| {
        return reader.takeByte() catch |e| {
            return switch (e) {
                std.io.Reader.Error.EndOfStream => std.math.maxInt(u32),
                std.io.Reader.Error.ReadFailed => MemoryError.HardwareError,
            };
        };
    } else return std.math.maxInt(u32);
}

pub fn step(self: *InputCharDev) void {
    _ = self;
}
