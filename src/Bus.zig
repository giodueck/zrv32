const std = @import("std");
const riscv = @import("riscv.zig");

const Bus = @This();

pub const MemoryError = error{
    IllegalInstruction,
    InstructionAccessFault,
    InstructionAddressMisaligned,
    LoadAddressMisaligned,
    LoadAccessFault,
    StoreAddressMisaligned,
    StoreAccessFault,
    HaltAddressWritten,
};

/// This can be used by implementations to mark ranges as having certain restrictions
pub const AccessControl = struct {
    read: bool = false,
    write: bool = false,
    execute: bool = false,
    io: bool = false,
};

pub const Width = enum(u3) { byte = 1, halfword = 2, word = 4, _ };

impl: *anyopaque,
/// PC reset address
_set: *const fn (*anyopaque, u32, u32, Width) void,
_get: *const fn (*anyopaque, u32, Width) u32,
_store: *const fn (*anyopaque, u32, u32, Width) MemoryError!void,
_load: *const fn (*anyopaque, u32, Width) MemoryError!u32,
_fetch: *const fn (*anyopaque, u32) MemoryError!u32,
_setCharDevWriter: *const fn (*anyopaque, *std.io.Writer) void,
_getStart: *const fn (*anyopaque) u32,
_stepDevices: *const fn (*anyopaque) void,
_getTimeAddrs: *const fn (*anyopaque) ?[4]u32,

/// Set the memory at the address to the value, truncated to width bytes.
/// The maximum width supported is 4, with the minimum being 1.
/// Illegal access or illegal width will fail silently, no traps are set using this method.
///
/// For access from an instruction, use the store method instead.
/// Writing to ROM is perfectly fine in this method, as it is not meant for emulator use.
pub fn set(self: Bus, addr: u32, value: u32, width: Width) void {
    self._set(self.impl, addr, value, width);
}

/// Called by the CPU when setting a value at a memory address.
/// Applies some restrictions to what memory ranges can be written to, and may fail depending on it.
pub fn store(self: Bus, addr: u32, value: u32, width: Width) MemoryError!void {
    try self._store(self.impl, addr, value, width);
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
pub fn get(self: Bus, addr: u32, width: Width) u32 {
    return self._get(self.impl, addr, width);
}

/// Called by the CPU when getting a value at a memory address.
/// Applies some restrictions to what memory ranges can be read from, and may fail depending on it.
/// width is the width in bytes, being at most 4.
pub fn load(self: Bus, addr: u32, width: Width) MemoryError!u32 {
    return self._load(self.impl, addr, width);
}

/// Called by the CPU when getting a value at a memory address for execution.
/// Applies some restrictions to what memory ranges can be executed from, and may fail depending on it.
pub fn fetch(self: Bus, addr: u32) MemoryError!u32 {
    return self._fetch(self.impl, addr);
}

/// Set the text output device writer
pub fn setCharDevWriter(self: Bus, writer: *std.io.Writer) void {
    return self._setCharDevWriter(self.impl, writer);
}

/// Get PC reset value
pub fn getStart(self: Bus) u32 {
    return self._getStart(self.impl);
}

pub fn stepDevices(self: Bus) void {
    return self._stepDevices(self.impl);
}

/// Get the addresses for mtime, mtimeh, mtimecmp and mtimecmph, in that order
pub fn getTimeAddrs(self: Bus) ?[4]u32 {
    return self._getTimeAddrs(self.impl);
}

pub fn implBy(impl_obj: anytype) Bus {
    const delegate = Bus.BusDelegate(impl_obj);
    return .{
        .impl = impl_obj,
        ._set = delegate.set,
        ._store = delegate.store,
        ._get = delegate.get,
        ._load = delegate.load,
        ._fetch = delegate.fetch,
        ._setCharDevWriter = delegate.setCharDevWriter,
        ._getStart = delegate.getStart,
        ._stepDevices = delegate.stepDevices,
        ._getTimeAddrs = delegate.getTimeAddrs,
    };
}

inline fn BusDelegate(impl_obj: anytype) type {
    const ImplType = @TypeOf(impl_obj);
    return struct {
        pub fn set(impl: *anyopaque, addr: u32, value: u32, width: Width) void {
            TPtr(ImplType, impl).set(addr, value, width);
        }
        pub fn store(impl: *anyopaque, addr: u32, value: u32, width: Width) MemoryError!void {
            try TPtr(ImplType, impl).store(addr, value, width);
        }
        pub fn get(impl: *anyopaque, addr: u32, width: Width) u32 {
            return TPtr(ImplType, impl).get(addr, width);
        }
        pub fn load(impl: *anyopaque, addr: u32, width: Width) MemoryError!u32 {
            return TPtr(ImplType, impl).load(addr, width);
        }
        pub fn fetch(impl: *anyopaque, addr: u32) MemoryError!u32 {
            return TPtr(ImplType, impl).fetch(addr);
        }
        pub fn setCharDevWriter(impl: *anyopaque, writer: *std.io.Writer) void {
            return TPtr(ImplType, impl).setCharDevWriter(writer);
        }
        pub fn getStart(impl: *anyopaque) u32 {
            return TPtr(ImplType, impl).start;
        }
        pub fn stepDevices(impl: *anyopaque) void {
            TPtr(ImplType, impl).stepDevices();
        }
        pub fn getTimeAddrs(impl: *anyopaque) ?[4]u32 {
            return TPtr(ImplType, impl).getTimeAddrs();
        }
    };
}

fn TPtr(T: type, opaque_ptr: *anyopaque) T {
    return @as(T, @ptrCast(@alignCast(opaque_ptr)));
}

pub fn isMisaligned(addr: u32, width: Width) bool {
    return switch (width) {
        .byte => false,
        .halfword => addr & 1 != 0,
        .word => addr & 3 != 0,
        else => true,
    };
}

pub fn ExceptionFromMemoryError(e: MemoryError) riscv.ExceptionCause {
    return switch (e) {
        MemoryError.IllegalInstruction => .IllegalInstruction,
        MemoryError.InstructionAccessFault => .InstructionAccessFault,
        MemoryError.InstructionAddressMisaligned => .InstructionAddressMisaligned,
        MemoryError.LoadAddressMisaligned => .LoadAddressMisaligned,
        MemoryError.LoadAccessFault => .LoadAccessFault,
        MemoryError.StoreAddressMisaligned => .StoreAddressMisaligned,
        MemoryError.StoreAccessFault => .StoreAccessFault,
        MemoryError.HaltAddressWritten => .HaltAddressWritten,
    };
}
