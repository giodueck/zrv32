const std = @import("std");
const MmioDevice = @import("MmioDevice.zig");
const Bus = @import("Bus.zig");
const MemoryError = Bus.MemoryError;
const Width = Bus.Width;

const OutputCharDev = @This();

io: ?std.Io = null,
writer: ?*std.Io.Writer = null,
addresses: [1]u32 = [1]u32{0},

pub fn init(self: *OutputCharDev, io: ?std.Io, writer: ?*std.Io.Writer, addrs: []const u32) void {
    self.io = io;
    self.writer = writer;
    for (0..self.addresses.len, addrs) |i, addr| {
        self.addresses[i] = addr;
    }
}

pub fn interface(self: *OutputCharDev) MmioDevice {
    return MmioDevice.implBy(self);
}

pub fn getAddresses(self: *OutputCharDev) []u32 {
    return &self.addresses;
}

pub fn store(self: *OutputCharDev, addr: u32, value: u32, width: Width) MemoryError!void {
    if (Bus.isMisaligned(addr, width)) return MemoryError.StoreAddressMisaligned;
    if (self.writer == null) {
        var threaded: std.Io.Threaded = .init_single_threaded;
        const io = if (self.io != null) self.io.? else threaded.io();

        var outbuf: [1024]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, &outbuf);
        const stdout = &stdout_writer.interface;
        defer stdout.flush() catch {};
        _ = stdout.write(&[_]u8{@truncate(value)}) catch {};
    } else {
        _ = self.writer.?.write(&[_]u8{@truncate(value)}) catch {};
        self.writer.?.flush() catch {};
    }
}

pub fn load(self: *OutputCharDev, addr: u32, width: Width) MemoryError!u32 {
    _ = self;
    if (Bus.isMisaligned(addr, width)) return MemoryError.LoadAddressMisaligned;
    return 0;
}

pub fn step(self: *OutputCharDev) void {
    _ = self;
}
