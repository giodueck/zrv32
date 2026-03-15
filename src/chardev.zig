const std = @import("std");

pub const CharDev = struct {
    /// When writer is null, stdout will be taken as a default value
    writer: ?*std.io.Writer = undefined,

    pub fn init(self: *@This(), writer: ?*std.io.Writer) void {
        self.writer = writer;
    }

    pub fn store(self: *@This(), addr: u32, value: u32, width: u32) void {
        _ = width;
        _ = addr;
        if (self.writer == null) {
            _ = std.fs.File.stdout().write(&[_]u8{@truncate(value)}) catch {};
        } else {
            _ = self.writer.?.write(&[_]u8{@truncate(value)}) catch {};
            self.writer.?.flush() catch {};
        }
    }

    pub fn load(self: *@This(), addr: u32, width: u32) u32 {
        _ = self;
        _ = addr;
        _ = width;
        return 0;
    }
};
