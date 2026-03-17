//! Defines an interface for memory-mapped I/O devices

const std = @import("std");
const Bus = @import("Bus.zig");
const MemoryError = Bus.MemoryError;
const Width = Bus.Width;

const MmioDevice = @This();

impl: *anyopaque,
addresses: []u32,
_store: *const fn (*anyopaque, u32, u32, Width) MemoryError!void,
_load: *const fn (*anyopaque, u32, Width) MemoryError!u32,

pub fn store(self: MmioDevice, addr: u32, value: u32, width: Width) MemoryError!void {
    try self._store(self.impl, addr, value, width);
}

pub fn load(self: MmioDevice, addr: u32, width: Width) MemoryError!u32 {
    return self._load(self.impl, addr, width);
}

pub fn implBy(impl_obj: anytype) MmioDevice {
    const delegate = MmioDevice.MmioDeviceDelegate(impl_obj);
    return .{
        .impl = impl_obj,
        .addresses = delegate.getAddresses(impl_obj),
        ._load = delegate.load,
        ._store = delegate.store,
    };
}

inline fn MmioDeviceDelegate(impl_obj: anytype) type {
    const ImplType = @TypeOf(impl_obj);
    return struct {
        pub fn store(impl: *anyopaque, addr: u32, value: u32, width: Width) MemoryError!void {
            try TPtr(ImplType, impl).store(addr, value, width);
        }
        pub fn load(impl: *anyopaque, addr: u32, width: Width) MemoryError!u32 {
            return TPtr(ImplType, impl).load(addr, width);
        }
        pub fn getAddresses(impl: *anyopaque) []u32 {
            return TPtr(ImplType, impl).getAddresses();
        }
    };
}

fn TPtr(T: type, opaque_ptr: *anyopaque) T {
    return @as(T, @ptrCast(@alignCast(opaque_ptr)));
}
