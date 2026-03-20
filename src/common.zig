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

        pub fn init(allocator: std.mem.Allocator) !@This() {
            const table = try allocator.alloc(?*Page, page_table_size);
            @memset(table, null);
            return .{
                .table = table,
            };
        }

        pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
            for (self.table) |page| {
                if (page) |p| {
                    allocator.free(p);
                }
            }
            allocator.free(self.table);
        }

        /// Set the element at the given index with the given value.
        /// If the corresponding page has not been created, an allocation occurs.
        pub fn set(self: *@This(), allocator: std.mem.Allocator, index: I, value: D) !void {
            const page_number: TI = @truncate(index >> @typeInfo(PI).int.bits);
            const page_index: PI = @truncate(index);
            if (self.table[page_number]) |page| {
                page[page_index] = value;
            } else {
                const page = try allocator.create(Page);
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
