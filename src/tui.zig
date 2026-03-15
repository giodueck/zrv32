//! TUI layout
//!
//! The layout focuses on making the emulator transparent and debugging easy.
//! It does not include a disassembler to show which line in a program is being run,
//! but it shows the state of the processor and output, and allows for fine-grained
//! control over execution.
//!
//! The layout is:
//!
//! ┌─────────────┐ ┌─────────────┐
//! │Real state   │ │Character    │
//! └─────────────┘ │output window│
//! ┌─────────────┐ │             │
//! │Logical state│ │             │
//! └─────────────┘ └─────────────┘

const std = @import("std");

const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const Cell = vaxis.Cell;
const TextView = vaxis.widgets.TextView;
const border = vaxis.widgets.border;

const Hart = @import("hart.zig").Hart;
const riscv = @import("riscv.zig");

// This can contain internal events as well as Vaxis events.
// Internal events can be posted into the same queue as vaxis events to allow
// for a single event loop with exhaustive switching. Booya
const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
    foo: u8,
};

pub fn tuiMain(allocator: std.mem.Allocator, hart: *Hart) !void {
    // Initialize a tty
    var buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(&buffer);
    defer tty.deinit();

    // Initialize Vaxis
    var vx = try vaxis.init(allocator, .{});
    // deinit takes an optional allocator. If your program is exiting, you can
    // choose to pass a null allocator to save some exit time.
    defer vx.deinit(allocator, tty.writer());

    // The event loop requires an intrusive init. We create an instance with
    // stable pointers to Vaxis and our TTY, then init the instance. Doing so
    // installs a signal handler for SIGWINCH on posix TTYs
    //
    // This event loop is thread safe. It reads the tty in a separate thread
    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();

    // Start the read loop. This puts the terminal in raw mode and begins
    // reading user input
    try loop.start();
    defer loop.stop();

    // Optionally enter the alternate screen
    try vx.enterAltScreen(tty.writer());

    // Real state view
    var state_text_view = TextView{ .scroll_view = .{ .vertical_scrollbar = .{ .character = .{ .grapheme = " " } } } };
    var state_text_view_buffer = TextView.Buffer{};
    defer state_text_view_buffer.deinit(allocator);

    // Logical (from the execution state PoV) state view
    var logical_state_text_view = TextView{ .scroll_view = .{ .vertical_scrollbar = .{ .character = .{ .grapheme = " " } } } };
    var logical_state_text_view_buffer = TextView.Buffer{};
    defer logical_state_text_view_buffer.deinit(allocator);

    // Text output writer
    var raw_output_writer = std.io.Writer.Allocating.init(allocator);
    defer raw_output_writer.deinit();
    hart.bus.setCharDevWriter(&raw_output_writer.writer);

    // Text output view
    var output_text_view = TextView{ .scroll_view = .{ .vertical_scrollbar = .{ .character = .{ .grapheme = " " } } } };
    var output_text_view_buffer = TextView.Buffer{};
    defer output_text_view_buffer.deinit(allocator);

    // Sends queries to terminal to detect certain features. This should always
    // be called after entering the alt screen, if you are using the alt screen
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);

    while (true) {
        // nextEvent blocks until an event is in the queue
        const event = loop.nextEvent();
        var step = false;

        // exhaustive switching ftw. Vaxis will send events if your Event enum
        // has the fields for those events (ie "key_press", "winsize")
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true }) or key.matches('q', .{})) {
                    break;
                } else if (key.matches('l', .{ .ctrl = true })) {
                    vx.queueRefresh();
                } else {
                    if (key.matches('s', .{})) step = true;
                }
            },

            // winsize events are sent to the application to ensure that all
            // resizes occur in the main thread. This lets us avoid expensive
            // locks on the screen. All applications must handle this event
            // unless they aren't using a screen (IE only detecting features)
            //
            // The allocations are because we keep a copy of each cell to
            // optimize renders. When resize is called, we allocated two slices:
            // one for the screen, and one for our buffered screen. Each cell in
            // the buffered screen contains an ArrayList(u8) to be able to store
            // the grapheme for that cell. Each cell is initialized with a size
            // of 1, which is sufficient for all of ASCII. Anything requiring
            // more than one byte will incur an allocation on the first render
            // after it is drawn. Thereafter, it will not allocate unless the
            // screen is resized
            .winsize => |ws| try vx.resize(allocator, tty.writer(), ws),
            else => {},
        }

        // vx.window() returns the root window. This window is the size of the
        // terminal and can spawn child windows as logical areas. Child windows
        // cannot draw outside of their bounds
        const win = vx.window();

        // Clear the entire space because we are drawing in immediate mode.
        // vaxis double buffers the screen. This new frame will be compared to
        // the old and only updated cells will be drawn
        win.clear();

        // Create a style for the borders
        const style: vaxis.Style = .{
            .fg = .{ .index = 4 },
        };

        // Step the emulator, if appropriate
        if (step and !hart.ebreak and hart.fatal_exception == null) {
            hart.step();
        }

        // Real state
        const state_win = win.child(.{
            .x_off = 2,
            .y_off = 1,
            .width = 50,
            .height = 28,
            .border = .{
                .where = .all,
                .style = style,
            },
        });

        const state_str = try hart.allocPrintState(allocator);
        defer allocator.free(state_str);
        try state_text_view_buffer.update(allocator, .{ .bytes = state_str });
        state_text_view.draw(state_win, state_text_view_buffer);

        // Logical state
        const logical_state_win = win.child(.{
            .x_off = 2,
            .y_off = 30,
            .width = 50,
            .height = 28,
            .border = .{
                .where = .all,
                .style = style,
            },
        });

        const highlight_style: vaxis.Style = .{
            .bg = .{ .index = 130 },
        };

        // This string will have highlights, which we must manually apply by setting a style
        var logical_state_str = try hart.allocPrintExecState(allocator);
        defer logical_state_str.deinit();
        try logical_state_text_view_buffer.update(allocator, .{ .bytes = logical_state_str.slice });
        try logical_state_text_view_buffer.updateStyle(allocator, .{ .style = highlight_style, .begin = logical_state_str.hi_begin, .end = logical_state_str.hi_end });
        logical_state_text_view.draw(logical_state_win, logical_state_text_view_buffer);

        // Text output
        const output_win = win.child(.{ .x_off = state_win.x_off + state_win.width + 2, .y_off = 1, .width = 80, .height = 28, .border = .{
            .where = .all,
            .style = style,
        } });

        try output_text_view_buffer.update(allocator, .{ .bytes = raw_output_writer.written() });
        output_text_view.draw(output_win, output_text_view_buffer);

        // Render the screen. Using a buffered writer will offer much better
        // performance, but is not required
        try vx.render(tty.writer());
    }
}
