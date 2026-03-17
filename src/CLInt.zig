const std = @import("std");
const Bus = @import("Bus.zig");
const MemoryError = Bus.MemoryError;
const Width = Bus.Width;
const MmioDevice = @import("MmioDevice.zig");

pub const CLInt = @This();

/// These addresses are: mtime, mtimeh, mtimecmp, mtimecmph (little-endian)
addresses: [4]u32 = [_]u32{0} ** 4,
/// These registers are: mtime, mtimeh, mtimecmp, mtimecmph (little-endian)
registers: [4]u32 = [_]u32{0} ** 4,

pub fn init(self: *CLInt, addrs: []const u32) void {
    for (0..self.addresses.len, addrs) |i, addr| {
        self.addresses[i] = addr;
    }
    for (0..self.registers.len) |i| {
        self.registers[i] = 0;
    }
}

pub fn interface(self: *CLInt) MmioDevice {
    return MmioDevice.implBy(self);
}

pub fn getAddresses(self: *CLInt) []u32 {
    return &self.addresses;
}

pub fn store(self: *CLInt, addr: u32, value: u32, width: Width) MemoryError!void {
    if (Bus.isMisaligned(addr, width)) return MemoryError.StoreAddressMisaligned;
    const index = std.mem.indexOfScalar(u32, &self.addresses, addr) orelse self.addresses.len;
    if (index < self.addresses.len) self.registers[index] = value;
}

pub fn load(self: *CLInt, addr: u32, width: Width) MemoryError!u32 {
    if (Bus.isMisaligned(addr, width)) return MemoryError.LoadAddressMisaligned;
    const index = std.mem.indexOfScalar(u32, &self.addresses, addr) orelse self.addresses.len;
    return if (index < self.addresses.len) self.registers[index] else 0;
}

pub fn step(self: *CLInt) void {
    // Can and should be more complex
    self.registers[0] +%= 1;
    if (self.registers[0] == 0) self.registers[1] +%= 1;
    // TODO interrupts
}
