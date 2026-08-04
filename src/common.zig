//! Common utilities

const std = @import("std");

/// Returns a SparseArray of data_type indexed with an index_type integer, divided into pages
/// indexed with a page_index_type integer.
///
/// index_type: must be an unsigned integer type, e.g. u32.
///
/// data_type: may be any arbitrary type.
///
/// page_index_type: must be an unsigned integer smaller than index_type, e.g. if index_type is
/// u32, page_index_type may be at most u31. A page_index_type of u12 would mean every page is
/// 2^12 values long
///
/// Call SparseArray(...).init() to create an instance, and .deinit() to deallocate it.
pub fn SparseArray(index_type: type, data_type: type, page_index_type: type) type {
    if (@typeInfo(index_type) != .int or @typeInfo(index_type).int.signedness != .unsigned) {
        @compileError("SparseArray expected an unsigned integer index_type, found " ++ @typeName(index_type));
    }
    if (@typeInfo(page_index_type) != .int or @typeInfo(page_index_type).int.signedness != .unsigned) {
        @compileError("SparseArray expected an unsigned integer index_type, found " ++ @typeName(page_index_type));
    } else if (@typeInfo(page_index_type).int.bits >= @typeInfo(index_type).int.bits) {
        @compileError("SparseArray expected page_index_type to be smaller than index_type. Expected smaller than " ++ @typeName(index_type) ++ ", found " ++ @typeName(page_index_type));
    }

    return struct {
        const I = index_type;
        const D = data_type;
        const PI = page_index_type;
        const TI = std.meta.Int(.unsigned, @typeInfo(I).int.bits - @typeInfo(PI).int.bits);
        const page_size = std.math.maxInt(PI) + 1;
        const page_table_size = std.math.maxInt(TI) + 1;
        const Page = [page_size]D;

        table: []?*Page,

        pub fn init(gpa: std.mem.Allocator) !@This() {
            const table = try gpa.alloc(?*Page, page_table_size);
            @memset(table, null);
            return .{
                .table = table,
            };
        }

        pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
            for (self.table) |page| {
                if (page) |p| {
                    gpa.destroy(p);
                }
            }
            gpa.free(self.table);
        }

        /// Set the element at the given index with the given value.
        /// If the corresponding page has not been created, an allocation occurs.
        pub fn set(self: *@This(), gpa: std.mem.Allocator, index: I, value: D) !void {
            const page_number: TI = @truncate(index >> @typeInfo(PI).int.bits);
            const page_index: PI = @truncate(index);
            if (self.table[page_number]) |page| {
                page[page_index] = value;
            } else {
                const page = try gpa.create(Page);
                @memset(page, 0);
                page[page_index] = value;
                self.table[page_number] = page;
            }
        }

        /// Get the element at the given index, if the page it lives in is allocated.
        pub fn get(self: *@This(), index: I) ?D {
            const page_number: TI = @truncate(index >> @typeInfo(PI).int.bits);
            const page_index: PI = @truncate(index);
            if (self.table[page_number]) |page| {
                return page[page_index];
            } else {
                return null;
            }
        }
    };
}

pub const QueueError = error {QueueFull, QueueEmpty};

/// A queue data structure with a fixed capacity
pub fn Queue(data_type: type) type {
    return struct {
        const T = data_type;

        gpa: std.mem.Allocator,

        ring: []T,
        /// Always indexes the value at the front of the queue. If it is equal to back, there
        /// is no value at the front and attempts to dequeue will return an error to indicate it.
        front: usize = 0,
        /// Indexes the position to enqueue items to. If enqueuing would lead to being equal
        /// to front, the operation returns an error indicating the queue is full.
        back: usize = 0,

        pub fn init(gpa: std.mem.Allocator, capacity: usize) !@This() {
            const ring = try gpa.alloc(T, capacity);
            return .{
                .gpa = gpa,
                .ring = ring,
                .front = 0,
                .back = 0,
            };
        }

        pub fn deinit(self: *@This()) void {
            self.gpa.free(self.ring);
        }

        /// Add an item to the queue
        pub fn enqueue(self: *@This(), item: T) QueueError!void {
            if ((self.front + self.back) % self.ring.len == self.ring.len - 1) {
                return QueueError.QueueFull;
            }
            self.ring[self.back] = item;
            self.back += 1;
            self.back %= self.ring.len;
        }

        /// Remove an item from the queue
        pub fn dequeue(self: *@This()) QueueError!T {
            if (self.front == self.back) {
                return QueueError.QueueEmpty;
            }
            const item = self.ring[self.front];
            self.front += 1;
            self.front %= self.ring.len;
            return item;
        }

        /// Get the item at the front of the queue without removing it
        pub fn peek(self: *@This()) QueueError!T {
            if (self.front == self.back) {
                return QueueError.QueueEmpty;
            }
            return self.ring[self.front];
        }

        /// Empty the queue without consuming its data
        pub fn clear(self: *@This()) void {
            self.front = 0;
            self.back = 0;
        }
    };
}
