const std = @import("std");
const MmioDevice = @import("MmioDevice.zig");
const Bus = @import("Bus.zig");
const MemoryError = Bus.MemoryError;
const Width = Bus.Width;

const CharDev = @This();

writer: ?*std.io.Writer = undefined,
addresses: [1]u32 = [1]u32{0},

pub fn init(self: *CharDev, writer: ?*std.io.Writer, addrs: []const u32) void {
    self.writer = writer;
    for (0..self.addresses.len, addrs) |i, addr| {
        self.addresses[i] = addr;
    }
}

pub fn interface(self: *CharDev) MmioDevice {
    return MmioDevice.implBy(self);
}

pub fn getAddresses(self: *CharDev) []u32 {
    return &self.addresses;
}

pub fn store(self: *CharDev, addr: u32, value: u32, width: Width) MemoryError!void {
    if (Bus.isMisaligned(addr, width)) return MemoryError.StoreAddressMisaligned;
    if (self.writer == null) {
        _ = std.fs.File.stdout().write(&[_]u8{@truncate(value)}) catch {};
    } else {
        _ = self.writer.?.write(&[_]u8{@truncate(value)}) catch {};
        self.writer.?.flush() catch {};
    }
}

pub fn load(self: *CharDev, addr: u32, width: Width) MemoryError!u32 {
    _ = self;
    if (Bus.isMisaligned(addr, width)) return MemoryError.LoadAddressMisaligned;
    return 0;
}
