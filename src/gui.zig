//! Graphical UI
//!
//! The layout focuses on making the emulator transparent and debugging easy.
//! It does not include a disassembler to show which line in a program is being run,
//! but it shows the state of the processor and output, and allows for fine-grained
//! control over execution.
//!
//! The advantage to the TUI is the ability to have complete control over the event
//! loop, which allows us to update the screen at fixed intervals without events
//! and run the emulator at full speed.
//!
//! The layout is:
//!
//! ┌──────────────────┐ ┌─────────────┐
//! │Logical/Real state│ │Character    │
//! │                  │ │output window│
//! │                  │ └─────────────┘
//! │                  │ ┌─────────────┐
//! │                  │ │Memory view  │
//! └──────────────────┘ └─────────────┘

const std = @import("std");

const rl = @import("raylib");
const rg = @import("raygui");

const genesis = @import("resources/style_genesis.zig");

const Hart = @import("hart.zig").Hart;
const riscv = @import("riscv.zig");

const hack_ttf = @embedFile("resources/Hack-Regular.ttf");
const charset = a: {
    const chars = "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
    var i32chars = [_]i32{0} ** chars.len;
    for (chars, 0..) |c, i| {
        i32chars[i] = c;
    }
    break :a i32chars;
};

const Screen = enum(u32) {
    state,
    memory,
    help,
};

const Mods = enum(u32) {
    Shift,
    Control,
    Alt,
};

const KeyBindHelp = struct {
    screen: Screen,
    keys: []const rl.KeyboardKey,
    mods: []const Mods = &.{},
    description: [:0]const u8,
};

const Keybinds = [_]KeyBindHelp{
    .{
        .screen = .state,
        .keys = &.{rl.KeyboardKey.h},
        .description = "Show this help screen",
    },
    .{
        .screen = .state,
        .keys = &.{rl.KeyboardKey.m},
        .description = "Switch to memory view settings",
    },
    .{
        .screen = .state,
        .keys = &.{rl.KeyboardKey.r},
        .description = "Reset the hart, which sets the CSRs and PC to their reset value",
    },
    .{
        .screen = .state,
        .keys = &.{rl.KeyboardKey.s},
        .description = "Step the emulator once, or hold down to step it on repeat",
    },
    .{
        .screen = .state,
        .keys = &.{rl.KeyboardKey.s},
        .mods = &.{.Shift},
        .description = "Toggle running the emulator continuously at the configured speed",
    },
    .{
        .screen = .state,
        .keys = &.{rl.KeyboardKey.t},
        .description = "Toggle between logical and real state view",
    },
    .{
        .screen = .state,
        .keys = &.{rl.KeyboardKey.comma},
        .description = "Reduce the frequency of the emulator when running continuously by 60 Hz",
    },
    .{
        .screen = .state,
        .keys = &.{rl.KeyboardKey.period},
        .description = "Increase the frequency of the emulator when running continuously by 60 Hz",
    },
    .{
        .screen = .state,
        .keys = &.{rl.KeyboardKey.comma},
        .mods = &.{.Shift},
        .description = "Halve the frequency of the emulator when running continuously",
    },
    .{
        .screen = .state,
        .keys = &.{rl.KeyboardKey.period},
        .mods = &.{.Shift},
        .description = "Double the frequency of the emulator when running continuously",
    },
    .{
        .screen = .state,
        .keys = &.{rl.KeyboardKey.f3},
        .description = "Show FPS counter",
    },

    .{
        .screen = .memory,
        .keys = &.{ rl.KeyboardKey.m, rl.KeyboardKey.escape },
        .description = "Return to previous screen",
    },

    .{
        .screen = .help,
        .keys = &.{ rl.KeyboardKey.h, rl.KeyboardKey.escape },
        .description = "Return to previous screen",
    },
};

pub fn guiMain(init: std.process.Init, hart: *Hart) !void {
    const io = init.io;
    const gpa = init.gpa;

    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 1000;
    const screenHeight = 600;

    rl.initWindow(screenWidth, screenHeight, "zrv32");
    defer rl.closeWindow(); // Close window and OpenGL context

    genesis.GuiLoadStyleGenesis();

    // Colors used in drawing
    const bg_color: rl.Color = colorFromInt(rg.getStyle(.default, .background_color));
    const title_color: rl.Color = colorFromInt(rg.getStyle(.default, .text_color_pressed));
    const text_color: rl.Color = colorFromInt(rg.getStyle(.default, .text_color_normal));
    const border_color: rl.Color = colorFromInt(rg.getStyle(.default, .border_color_normal));
    const highlight_color: rl.Color = colorFromInt(rg.getStyle(.default, .base_color_pressed));
    const keybind_color: rl.Color = colorFromInt(rg.getStyle(.default, .base_color_pressed));
    const semaphore_colors: [3]rl.Color = [_]rl.Color{ .red, .yellow, .green };

    // Section titles
    const state_view_title = "Real Hart State";
    const logical_state_view_title = "Logical Hart State";
    const text_output_view_title = "Output";
    const memory_view_title = "Memory";
    const memory_settings_view_title = "Memory settings";
    const help_view_title = "Keybind help";

    // Real hart state
    var state_str = try hart.allocPrintState(gpa);
    var state_cstr: [:0]u8 = try gpa.dupeZ(u8, state_str);
    defer gpa.free(state_str);
    defer gpa.free(state_cstr);

    // Logical hart state
    var logical_state_str = try hart.allocPrintLogicalState(gpa);
    defer logical_state_str.deinit();

    // Standalone CSR and priv state, which is not appended to the logical state
    var csr_state_str = try hart.allocPrintCSRs(gpa);
    defer gpa.free(csr_state_str);

    // Text output writer
    var text_output_writer = std.Io.Writer.Allocating.init(gpa);
    defer text_output_writer.deinit();
    hart.bus.setOutputCharDevWriter(io, &text_output_writer.writer);
    var text_output_cstr = try gpa.dupeZ(u8, text_output_writer.written());
    defer gpa.free(text_output_cstr);

    // Text input writer
    var text_input_writer = std.Io.Writer.Allocating.init(gpa);
    defer text_input_writer.deinit();
    var text_input_slice: []u8 = try gpa.dupe(u8, text_input_writer.written());
    defer gpa.free(text_input_slice);
    var text_input_reader = std.Io.Reader.fixed(text_input_slice);
    hart.bus.setInputCharDevReader(&text_input_reader);

    // Memory view buffer
    const memory_view_buffer = try gpa.allocSentinel(u8, 2048, 0);
    defer gpa.free(memory_view_buffer);
    var memory_view_cstr: [:0]u8 = undefined; // must be defined in the first loop iteration
    var memory_view_address: u32 = hart.bus.getStart();
    const memory_view_guide_buffer = try gpa.alloc(u8, 2048);
    defer gpa.free(memory_view_guide_buffer);
    var memory_view_guide_cstr: [:0]u8 = undefined; // must be defined in the first loop iteration

    // Memory settings view text input buffer
    var memory_settings_input_writer = std.Io.Writer.Allocating.init(gpa);
    try memory_settings_input_writer.writer.writeAll("0x");
    defer memory_settings_input_writer.deinit();

    const input_buffer = try gpa.allocSentinel(u8, 2048, 0);
    @memset(input_buffer, 0);
    defer gpa.free(input_buffer);

    // General purpose text buffer
    const gp_buffer = try gpa.allocSentinel(u8, 2048, 0);
    defer gpa.free(gp_buffer);

    // Use a monospaced font instead of the default
    const font = try rl.loadFontFromMemory(".ttf", hack_ttf, 16, &charset);
    defer rl.unloadFont(font);
    const font_height = 18;
    const font_width = 8;

    rg.setFont(font);

    const title_font = try rl.loadFontFromMemory(".ttf", hack_ttf, 20, &charset);
    defer rl.unloadFont(title_font);

    const target_fps = 60;
    rl.setTargetFPS(target_fps); // Set our game to run at 60 frames-per-second
    rl.setExitKey(.null); // Unset ESC as the default exit key
    //--------------------------------------------------------------------------------------

    // Main loop variables
    var screen_stack = try std.ArrayList(Screen).initCapacity(gpa, 16);
    defer screen_stack.deinit(gpa);
    screen_stack.appendAssumeCapacity(.state);

    var show_fps = false;

    // State screen variables
    var show_logical_state = true;
    var run = false;
    var run_steps: u32 = 16; // Steps per frame
    var halted = false;
    var step_indicator: u32 = 0; // For indicating the emulator is running for a few frames if only a step was taken
    const step_indicator_count = 5;

    // Memory settings screen variables
    var invalid_character: ?u8 = null;

    // Drawing constants
    const view_offset = rl.Vector2.init(24, 24); // in pixels
    // State window will take up a fixed size
    const state_view_size_chars = rl.Vector2.init(48, 29); // in characters
    // Memory dump output will take up a variable width
    const memory_view_size_chars = rl.Vector2.init(16 * 3 + 2 + 9, 9 + 1); // in characters
    // Text output will take up a variable width and height
    const text_output_view_offset = view_offset.add(state_view_size_chars.multiply(.{ .x = font_width, .y = 0 })).add(.{ .x = view_offset.x, .y = 0 });
    const text_output_view_size_chars = rl.Vector2.init(@round((screenWidth - view_offset.x * 3 - (state_view_size_chars.x * font_width)) / font_width), state_view_size_chars.y - memory_view_size_chars.y - view_offset.y / font_height); // in characters
    var text_output_view_textbox: TextBox = .{
        .font = font,
        .rect = rl.Rectangle.init(
            text_output_view_offset.x + 1 * font_width,
            text_output_view_offset.y + 1 * font_height,
            font_width * text_output_view_size_chars.x - 2 * font_width,
            font_height * text_output_view_size_chars.y - 1 * font_height,
        ),
        .font_size = 16,
        .spacing = 0,
        .word_wrap = false,
        .color = text_color,
    };
    const text_output_rec = rl.Rectangle.init(text_output_view_offset.x, text_output_view_offset.y, font_width * text_output_view_size_chars.x, font_height * text_output_view_size_chars.y);
    // Memory dump will show below text output
    const memory_view_offset = view_offset.add(state_view_size_chars.multiply(.{ .x = font_width, .y = 0 })).add(text_output_view_size_chars.multiply(.{ .x = 0, .y = font_height }).add(view_offset)); // in pixels
    var memory_view_textbox: TextBox = .{
        .font = font,
        .rect = rl.Rectangle.init(
            memory_view_offset.x + 1 * font_width,
            memory_view_offset.y + 1 * font_height,
            font_width * memory_view_size_chars.x - 2 * font_width,
            font_height * memory_view_size_chars.y - 1 * font_height,
        ),
        .font_size = 16,
        .spacing = 0,
        .word_wrap = false,
        .color = text_color,
    };
    // Memory screen view
    const memory_settings_view_size_chars = rl.Vector2.init(@round((screenWidth - view_offset.x * 2) / font_width), state_view_size_chars.y - view_offset.y / font_height); // in characters
    const memory_settings_input_size_chars = rl.Vector2.init(10, 1); // in characters
    // Help screen view
    const help_view_size_chars = rl.Vector2.init(@round((screenWidth - view_offset.x * 2) / font_width), state_view_size_chars.y - view_offset.y / font_height); // in characters

    // Main loop
    var update_outputs = true;
    while (!rl.windowShouldClose()) {
        defer step_indicator -|= 1;

        const current_screen = screen_stack.getLast();

        // Update
        //----------------------------------------------------------------------------------
        var step = false;
        var reset = false;

        switch (current_screen) {
            .state => {
                // ==== Keyboard Inputs ====

                // TODO indicator for this
                const text_focused = rl.checkCollisionPointRec(rl.getMousePosition(), text_output_rec);

                // Non-text inputs
                if (rl.isKeyPressed(.f3)) {
                    show_fps = !show_fps;
                }

                if (!text_focused) {
                    if (rl.isKeyPressed(.s) or rl.isKeyPressedRepeat(.s)) {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            run = !run;
                        } else {
                            step = true;
                            step_indicator = step_indicator_count;
                        }
                    }
                    if (rl.isKeyPressed(.r)) {
                        reset = true;
                    }
                    if (rl.isKeyPressed(.t)) {
                        show_logical_state = !show_logical_state;
                        update_outputs = true;
                    }
                    if (rl.isKeyPressed(.period) or rl.isKeyPressedRepeat(.period)) {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            run_steps <<|= 1;
                        } else {
                            run_steps +|= 1;
                        }
                    }
                    if (rl.isKeyPressed(.comma) or rl.isKeyPressedRepeat(.comma)) {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            if (run_steps >= 2) run_steps >>= 1;
                        } else if (run_steps > 1) {
                            run_steps -= 1;
                        }
                    }

                    // Switch screens, cancel all previous inputs that advance the emulator
                    if (rl.isKeyPressed(.m)) {
                        try screen_stack.append(gpa, .memory);
                        step = false;
                        reset = false;
                        run = false;
                    }
                    if (rl.isKeyPressed(.h)) {
                        try screen_stack.append(gpa, .help);
                        step = false;
                        reset = false;
                        run = false;
                    }
                } else {
                    // Write all text into the text_input_reader
                    if (try getTypedText(&text_input_writer.writer)) {
                        // If new text was written, update the reader
                        const unread = try text_input_reader.allocRemaining(gpa, .unlimited);
                        defer gpa.free(unread);
                        const written = try text_input_writer.toOwnedSlice();
                        defer gpa.free(written);
                        try text_input_writer.writer.writeAll(unread);
                        try text_input_writer.writer.writeAll(written);
                        gpa.free(text_input_slice);
                        text_input_slice = try text_input_writer.toOwnedSlice();
                        text_input_reader = std.Io.Reader.fixed(text_input_slice);
                        std.debug.print("{s}\n", .{text_input_slice});
                        hart.bus.setInputCharDevReader(&text_input_reader);
                    }
                }

                // ==== Raygui elements ====

                // Hart state
                if (show_logical_state) {
                    _ = rg.groupBox(.init(view_offset.x, view_offset.y, font_width * state_view_size_chars.x, font_height * state_view_size_chars.y), logical_state_view_title);
                } else {
                    _ = rg.groupBox(.init(view_offset.x, view_offset.y, font_width * state_view_size_chars.x, font_height * state_view_size_chars.y), state_view_title);
                }
                // Text output
                _ = rg.groupBox(text_output_rec, text_output_view_title);
                // Memory inspector
                _ = rg.groupBox(.init(memory_view_offset.x, memory_view_offset.y, font_width * memory_view_size_chars.x, font_height * memory_view_size_chars.y), memory_view_title);

                // ==== Logic ====

                // Run emulator
                if (hart.ebreak or hart.fatal_exception != null) {
                    run = false;
                    step = false;
                    halted = true;
                }
                if (run) {
                    for (0..run_steps) |_| {
                        if (hart.ebreak or hart.fatal_exception != null) break;
                        hart.step();
                    }
                    update_outputs = true;
                } else if (step) {
                    hart.step();
                    update_outputs = true;
                } else if (reset) {
                    hart.reset();
                    text_output_writer.clearRetainingCapacity();
                    gpa.free(text_output_cstr);
                    text_output_cstr = try gpa.dupeZ(u8, "");
                    update_outputs = true;
                    halted = false;
                }

                // Update outputs
                if (update_outputs) {
                    update_outputs = false;
                    if (show_logical_state) {
                        logical_state_str.deinit();
                        logical_state_str = try hart.allocPrintLogicalState(gpa);

                        gpa.free(csr_state_str);
                        csr_state_str = try hart.allocPrintCSRs(gpa);
                    } else {
                        gpa.free(state_str);
                        gpa.free(state_cstr);
                        state_str = try hart.allocPrintState(gpa);
                        state_cstr = try gpa.dupeZ(u8, state_str);
                    }

                    if (text_output_writer.written().len > 0) {
                        gpa.free(text_output_cstr);

                        text_output_cstr = try gpa.dupeZ(u8, text_output_writer.written());

                        // Clear contents and write back only the portion rendered in the last frame
                        if (text_output_view_textbox.last_scroll_skip_end > 1000) {
                            text_output_writer.clearRetainingCapacity();
                            text_output_writer.writer.writeAll(text_output_cstr[@intCast(text_output_view_textbox.last_scroll_skip_end)..]) catch unreachable;
                            text_output_view_textbox.last_scroll_skip_end = 0;

                            // Then redupe the C str
                            gpa.free(text_output_cstr);
                            text_output_cstr = try gpa.dupeZ(u8, text_output_writer.written());
                        }
                    }

                    const mem = try hart.bus.getSlice(gpa, memory_view_address & 0xFFFF_FF80, 0x80);
                    defer gpa.free(mem);
                    memory_view_cstr = try bufPrintMemoryDump(memory_view_buffer, mem);
                    memory_view_guide_cstr = try bufPrintMemoryDumpGuide(memory_view_guide_buffer, memory_view_address & 0xFFFF_FF80);
                }
            },
            .memory => {
                // ==== Keyboard Inputs ====

                if (rl.isKeyPressed(.m) or rl.isKeyPressed(.escape)) {
                    _ = screen_stack.pop();
                }
                if (rl.isKeyPressed(.h)) {
                    try screen_stack.append(gpa, .help);
                }

                // ==== Raygui elements ====

                if (screen_stack.getLast() == .memory) {
                    _ = rg.groupBox(.init(view_offset.x, view_offset.y, memory_settings_view_size_chars.x * font_width, memory_settings_view_size_chars.y * font_height), memory_settings_view_title);

                    const label_text = "Address (hex, no '0x' prefix): ";
                    const input_rect = rl.Rectangle.init(view_offset.x * 2 + @as(f32, @floatFromInt(rg.getTextWidth(label_text))), view_offset.y * 2, memory_settings_input_size_chars.x * font_width, memory_settings_input_size_chars.y * font_height);
                    var label_rect = input_rect;
                    label_rect.x -= @as(f32, @floatFromInt(rg.getTextWidth(label_text)));
                    label_rect.width += @as(f32, @floatFromInt(rg.getTextWidth(label_text)));
                    _ = rg.label(label_rect, label_text);

                    _ = rg.textBox(input_rect, input_buffer, true);

                    label_rect.y += font_height;
                    if (invalid_character) |c| {
                        _ = rg.label(label_rect, try std.fmt.bufPrintZ(gp_buffer, "Invalid character: '{c}'", .{c}));
                    }

                    // ==== Logic ====

                    // With QMK keyboards, layer tap keys tapped don't always get detected by games as having been pressed.
                    // For some reason, the workaround is to get all keys pressed, which does reliably detect it.
                    var k = rl.getKeyPressed();
                    while (k != .null) : (k = rl.getKeyPressed()) {
                        switch (k) {
                            .enter => {
                                memory_view_address = addrparse: {
                                    invalid_character = null;
                                    var addr: u32 = 0;
                                    if (input_buffer[0] == 0) break :addrparse memory_view_address;
                                    for (input_buffer[0..9 :0]) |c| {
                                        switch (c) {
                                            '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                                                addr <<= 4;
                                                addr += c - '0';
                                            },
                                            'a', 'b', 'c', 'd', 'e', 'f' => {
                                                addr <<= 4;
                                                addr += c - 'a' + 10;
                                            },
                                            'A', 'B', 'C', 'D', 'E', 'F' => {
                                                addr <<= 4;
                                                addr += c - 'A' + 10;
                                            },
                                            0 => {
                                                // End of string
                                                break;
                                            },
                                            else => {
                                                // Keep old value
                                                invalid_character = c;
                                                break :addrparse memory_view_address;
                                            },
                                        }
                                    }
                                    break :addrparse addr;
                                };

                                if (invalid_character == null) {
                                    update_outputs = true;
                                    _ = screen_stack.pop();
                                    break;
                                }
                            },
                            else => {},
                        }
                    }
                }
            },
            .help => {
                if (rl.isKeyPressed(.h) or rl.isKeyPressed(.escape)) {
                    _ = screen_stack.pop();
                }

                if (screen_stack.getLast() == .help) {
                    _ = rg.groupBox(.init(view_offset.x, view_offset.y, help_view_size_chars.x * font_width, help_view_size_chars.y * font_height), help_view_title);
                }
            },
        }
        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(bg_color);

        if (show_fps) rl.drawFPS(5, screenHeight - 20);

        switch (current_screen) {
            .state => {
                // ==== Hart state ====
                if (show_logical_state) {
                    const full_logical_cstr = try std.fmt.bufPrintZ(gp_buffer, "{s}{s}", .{ logical_state_str.slice, csr_state_str });

                    // This text has highlight information
                    if (logical_state_str.hi_end > logical_state_str.hi_begin) {
                        var line: i32 = 1;
                        var column: i32 = 0;
                        for (logical_state_str.slice, 0..) |ch, i| {
                            column += 1;
                            if (i == logical_state_str.hi_begin) break;
                            if (ch == '\n') {
                                line += 1;
                                column = 0;
                            }
                        }
                        rl.drawRectangleRounded(.{ .x = @floatFromInt(@as(i32, @intFromFloat(view_offset.x)) + column * font_width - 1), .y = @floatFromInt(@as(i32, @intFromFloat(view_offset.y)) + line * font_height - 1), .width = @floatFromInt(font_width * @as(i32, @intCast(logical_state_str.hi_end - logical_state_str.hi_begin)) + 2), .height = @floatFromInt(font_height) }, 0.2, 2, highlight_color);
                    }

                    rl.drawTextEx(font, full_logical_cstr, view_offset.add(.{ .x = font_width, .y = font_height }), @floatFromInt(font.baseSize), 0, text_color);
                } else {
                    rl.drawTextEx(font, state_cstr, view_offset.add(.{ .x = font_width, .y = font_height }), @floatFromInt(font.baseSize), 0, text_color);
                }

                // Hart frequency
                const freq_cstr = try std.fmt.bufPrintZ(gp_buffer, "{d} Hz", .{@as(u64, run_steps) * target_fps});
                rl.drawTextEx(font, freq_cstr, view_offset.add(.{ .x = (state_view_size_chars.x - 3) * font_width - @as(f32, @floatFromInt(freq_cstr.len * font_width)), .y = 3 }), 16, 0, highlight_color);

                // Running indicator
                rl.drawCircle(@as(i32, @intFromFloat(view_offset.x)) + @as(i32, @intFromFloat(state_view_size_chars.x - 2)) * font_width + @divTrunc(font_width, 2), @as(i32, @intFromFloat(view_offset.y)) + @divTrunc(font_height, 2) + 2, 6, if (halted) semaphore_colors[0] else if (run or step_indicator > 0) semaphore_colors[2] else semaphore_colors[1]);

                // ==== Text output ====
                text_output_view_textbox.drawText(text_output_cstr);

                // ==== Memory inspector ====
                memory_view_textbox.color = border_color;
                memory_view_textbox.drawText(memory_view_guide_cstr);
                memory_view_textbox.color = text_color;
                memory_view_textbox.drawText(memory_view_cstr);
            },

            .memory => {},

            .help => {
                // Show all keybinds for each screen
                var line: i32 = 1;
                inline for (@typeInfo(Screen).@"enum".fields) |s| {
                    const section_title = comptime switch (@as(Screen, @enumFromInt(s.value))) {
                        .state => "Emulator",
                        .memory => "Memory settings",
                        .help => "Keybind help",
                    };
                    rl.drawTextEx(font, section_title, view_offset.add(.{ .x = font_width, .y = @floatFromInt(line * font_height) }), 16, 0, title_color);
                    line += 1;

                    for (Keybinds) |bind| {
                        if (@intFromEnum(bind.screen) == s.value) {
                            var offset: i32 = 0;
                            for (bind.keys, 0..) |key, i| {
                                if (i > 0) {
                                    rl.drawTextEx(font, ", ", view_offset.add(.{ .x = @floatFromInt((2 + offset) * font_width), .y = @floatFromInt(line * font_height) }), 16, 0, keybind_color);
                                    offset += 2;
                                }
                                for (bind.mods) |mod| {
                                    rl.drawTextEx(font, @tagName(mod), view_offset.add(.{ .x = @floatFromInt((2 + offset) * font_width), .y = @floatFromInt(line * font_height) }), 16, 0, keybind_color);
                                    offset += @intCast(@tagName(mod).len);
                                    rl.drawTextEx(font, " + ", view_offset.add(.{ .x = @floatFromInt((2 + offset) * font_width), .y = @floatFromInt(line * font_height) }), 16, 0, keybind_color);
                                    offset += 3;
                                }

                                rl.drawTextEx(font, getKeyName(key), view_offset.add(.{ .x = @floatFromInt((2 + offset) * font_width), .y = @floatFromInt(line * font_height) }), 16, 0, keybind_color);
                                offset += @intCast(getKeyName(key).len);
                            }
                            rl.drawTextEx(font, ": ", view_offset.add(.{ .x = @floatFromInt((2 + offset) * font_width), .y = @floatFromInt(line * font_height) }), 16, 0, text_color);
                            offset += 2;

                            rl.drawTextEx(font, bind.description, view_offset.add(.{ .x = @floatFromInt((2 + offset) * font_width), .y = @floatFromInt(line * font_height) }), 16, 0, text_color);
                            line += 1;
                        }
                    }
                }
            },
        }

        // TODO redo this with raygui
        // // Draw help hint
        // rl.drawTextEx(font, "Press ", view_offset.add(state_view_size_chars.multiply(.{ .x = 0, .y = font_height })).add(.{ .x = 0, .y = font_height }), 16, 0, secondary_text_color);
        // rl.drawTextEx(font, "h", view_offset.add(state_view_size_chars.multiply(.{ .x = 0, .y = font_height })).add(.{ .x = font_width * 6, .y = font_height }), 16, 0, keybind_color);
        // rl.drawTextEx(font, " for help", view_offset.add(state_view_size_chars.multiply(.{ .x = 0, .y = font_height })).add(.{ .x = font_width * 7, .y = font_height }), 16, 0, secondary_text_color);
        //----------------------------------------------------------------------------------
    }
}

// Some keys don't have a name and cause assertion failures
fn getKeyName(key: rl.KeyboardKey) [:0]const u8 {
    return switch (key) {
        .escape => return "Escape",
        .f3 => return "F3",
        else => rl.getKeyName(key),
    };
}

/// Draw text constrained by a rectangle and with wrapping on characters or space-separated words
const TextBox = struct {
    rect: rl.Rectangle,
    font: rl.Font,
    font_size: f32,
    spacing: f32,
    color: rl.Color,
    word_wrap: bool,
    tabstop: i32 = 4,
    /// Follow the bottom of the text
    bottom: bool = true,
    /// Last drawText call skipped all characters up to this index
    last_scroll_skip_end: isize = -1,

    // TODO text preprocessing function to handle backspace, tabs and other special characters before drawing
    pub fn drawText(self: *@This(), text: [:0]const u8) void {
        var text_offset: rl.Vector2 = .{ .x = 0, .y = 0 };
        var column: i32 = 0; // For tab expansion
        self.last_scroll_skip_end = -1;

        var scroll = if (self.bottom) self.textHeight(text) - self.maxLines() else 0;
        if (scroll < 0) scroll = 0;

        const scale_factor = self.font_size / @as(f32, @floatFromInt(self.font.baseSize)); // Character rectangle scaling factor

        // Index to begin drawing a line
        var start_line: i32 = -1;
        // Index to stop drawing a line
        var end_line: i32 = -1;
        // Last value of the character position
        var last_char: i32 = -1;

        // State machine variables
        const State = enum { measure, draw };
        var state: State = if (self.word_wrap) .measure else .draw;

        var i: i32 = 0;
        var k: i32 = 0;
        while (i < text.len) : ({
            i += 1;
            k += 1;
        }) {
            var codepoint_byte_count: i32 = 0;
            const codepoint = rl.getCodepoint(text[@intCast(i)..], &codepoint_byte_count);
            const index: usize = @intCast(rl.getGlyphIndex(self.font, codepoint));

            if (codepoint == 0x3f) codepoint_byte_count = 1;
            i += @intCast(codepoint_byte_count - 1);

            var glyph_width: f32 = 0;
            var tab_width: i32 = 0;
            if (codepoint != '\n') {
                glyph_width = if (self.font.glyphs[index].advanceX == 0) self.font.recs[index].width * scale_factor else @as(f32, @floatFromInt(self.font.glyphs[index].advanceX));

                // Expand tabs
                if (codepoint == '\t') {
                    tab_width = self.tabstop - @mod(column, self.tabstop);
                    tab_width = if (tab_width > 0) tab_width else self.tabstop;
                    const space_index: usize = @intCast(rl.getGlyphIndex(self.font, ' '));
                    glyph_width = @as(f32, @floatFromInt(tab_width)) * @as(f32, @floatFromInt(self.font.glyphs[space_index].advanceX));
                }

                if (i + 1 < text.len) glyph_width += self.spacing;
            }

            if (state == .measure) {
                // Word delimiters
                if (codepoint == ' ' or codepoint == '\t' or codepoint == '\n') end_line = @intCast(i);

                if (text_offset.x + glyph_width > self.rect.width) {
                    end_line = if (end_line < 1) @intCast(i) else end_line;
                    if (i == end_line) end_line -= codepoint_byte_count;
                    if (start_line + codepoint_byte_count == end_line) end_line = i - codepoint_byte_count;

                    state = .draw;
                } else if (i + 1 == text.len) {
                    end_line = i;
                    state = .draw;
                } else if (codepoint == '\n') {
                    state = .draw;
                }

                if (state == .draw) {
                    text_offset.x = 0;
                    column = 0;
                    i = start_line;
                    glyph_width = 0;

                    // Save character position when switching states
                    const tmp = last_char;
                    last_char = k - 1;
                    k = tmp;
                }
            } else {
                // state == .draw
                if (codepoint == '\n') {
                    if (!self.word_wrap) {
                        const bs: f32 = @floatFromInt(self.font.baseSize);
                        if (scroll > 0) scroll -= 1 else text_offset.y += bs * scale_factor;
                        text_offset.x = 0;
                        column = 0;
                    }
                } else {
                    if (!self.word_wrap and text_offset.x + glyph_width > self.rect.width) {
                        const bs: f32 = @floatFromInt(self.font.baseSize);
                        if (scroll > 0) scroll -= 1 else text_offset.y += bs * scale_factor;
                        text_offset.x = 0;
                        column = 0;
                    }

                    // When text overflows rectangle height, stop drawing
                    if (text_offset.y + @as(f32, @floatFromInt(self.font.baseSize)) * scale_factor > self.rect.height) break;

                    // Draw current character glyph
                    if (scroll == 0 and codepoint != ' ' and codepoint != '\t') {
                        if (self.last_scroll_skip_end < 0) self.last_scroll_skip_end = @intCast(i);
                        rl.drawTextCodepoint(self.font, codepoint, text_offset.add(.{ .x = self.rect.x, .y = self.rect.y }), self.font_size, self.color);
                    }
                }

                if (self.word_wrap and i == end_line) {
                    const bs: f32 = @floatFromInt(self.font.baseSize);
                    if (scroll > 0) scroll -= 1 else text_offset.y += bs * scale_factor;
                    text_offset.x = 0;
                    column = 0;
                    start_line = end_line;
                    end_line = -1;
                    glyph_width = 0;
                    k = last_char;

                    state = if (state == .draw) .measure else .draw;
                }
            }

            // No filtering by codepoint or spaces, leading spaces are a feature
            text_offset.x += glyph_width;
            column += if (glyph_width > 0) (if (codepoint == '\t') tab_width else 1) else 0;
        }
    }

    /// Returns the number of lines the text would take up in this TextBox, accounting for wrapped lines
    pub fn textHeight(self: @This(), text: [:0]const u8) i32 {
        var text_offset: rl.Vector2 = .{ .x = 0, .y = 0 };
        var column: i32 = 0; // For tab expansion
        var line: i32 = 0;

        const scale_factor = self.font_size / @as(f32, @floatFromInt(self.font.baseSize)); // Character rectangle scaling factor

        // Index to begin drawing a line
        var start_line: i32 = -1;
        // Index to stop drawing a line
        var end_line: i32 = -1;
        // Last value of the character position
        var last_char: i32 = -1;

        // State machine variables
        const State = enum { measure, draw };
        var state: State = if (self.word_wrap) .measure else .draw;

        var i: i32 = 0;
        var k: i32 = 0;
        while (i < text.len) : ({
            i += 1;
            k += 1;
        }) {
            var codepoint_byte_count: i32 = 0;
            const codepoint = rl.getCodepoint(text[@intCast(i)..], &codepoint_byte_count);
            const index: usize = @intCast(rl.getGlyphIndex(self.font, codepoint));

            if (codepoint == 0x3f) codepoint_byte_count = 1;
            i += @intCast(codepoint_byte_count - 1);

            var glyph_width: f32 = 0;
            var tab_width: i32 = 0;
            if (codepoint != '\n') {
                glyph_width = if (self.font.glyphs[index].advanceX == 0) self.font.recs[index].width * scale_factor else @as(f32, @floatFromInt(self.font.glyphs[index].advanceX));

                // Expand tabs
                if (codepoint == '\t') {
                    tab_width = self.tabstop - @mod(column, self.tabstop);
                    tab_width = if (tab_width > 0) tab_width else self.tabstop;
                    const space_index: usize = @intCast(rl.getGlyphIndex(self.font, ' '));
                    glyph_width = @as(f32, @floatFromInt(tab_width)) * @as(f32, @floatFromInt(self.font.glyphs[space_index].advanceX));
                }

                if (i + 1 < text.len) glyph_width += self.spacing;
            }

            if (state == .measure) {
                // Word delimiters
                if (codepoint == ' ' or codepoint == '\t' or codepoint == '\n') end_line = @intCast(i);

                if (text_offset.x + glyph_width > self.rect.width) {
                    end_line = if (end_line < 1) @intCast(i) else end_line;
                    if (i == end_line) end_line -= codepoint_byte_count;
                    if (start_line + codepoint_byte_count == end_line) end_line = i - codepoint_byte_count;

                    state = .draw;
                } else if (i + 1 == text.len) {
                    end_line = i;
                    state = .draw;
                } else if (codepoint == '\n') {
                    state = .draw;
                }

                if (state == .draw) {
                    text_offset.x = 0;
                    column = 0;
                    i = start_line;
                    glyph_width = 0;

                    // Save character position when switching states
                    const tmp = last_char;
                    last_char = k - 1;
                    k = tmp;
                }
            } else {
                // state == .draw
                // This state is coopted to just count instead of actually drawing anything
                if (codepoint == '\n') {
                    if (!self.word_wrap) {
                        const bs: f32 = @floatFromInt(self.font.baseSize);
                        text_offset.y += bs * scale_factor;
                        text_offset.x = 0;
                        column = 0;
                        line += 1;
                    }
                } else {
                    if (!self.word_wrap and text_offset.x + glyph_width > self.rect.width) {
                        const bs: f32 = @floatFromInt(self.font.baseSize);
                        text_offset.y += bs * scale_factor;
                        text_offset.x = 0;
                        column = 0;
                        line += 1;
                    }
                }

                if (self.word_wrap and i == end_line) {
                    const bs: f32 = @floatFromInt(self.font.baseSize);
                    text_offset.y += bs * scale_factor;
                    text_offset.x = 0;
                    column = 0;
                    line += 1;
                    start_line = end_line;
                    end_line = -1;
                    glyph_width = 0;
                    k = last_char;

                    state = if (state == .draw) .measure else .draw;
                }
            }

            // No filtering by codepoint or spaces, leading spaces are a feature
            text_offset.x += glyph_width;
            column += if (glyph_width > 0) (if (codepoint == '\t') tab_width else 1) else 0;
        }

        return line + @as(i32, if (text.len > 0) 1 else 0);
    }

    pub fn maxLines(self: @This()) i32 {
        const scale_factor = self.font_size / @as(f32, @floatFromInt(self.font.baseSize)); // Character rectangle scaling factor

        return @intFromFloat(self.rect.height / @as(f32, @floatFromInt(self.font.baseSize)) * scale_factor);
    }
};

/// Prints a memory dump as a C string, stored on buf.
fn bufPrintMemoryDump(buf: []u8, dump: []?u8) ![:0]u8 {
    var sep: []const u8 = "\n         ";
    @memset(buf, 0);
    var fba = std.heap.FixedBufferAllocator.init(buf);
    var writer = std.Io.Writer.Allocating.init(fba.allocator());
    for (dump, 0..) |byte, i| {
        if (byte == null) {
            try writer.writer.print("{s}--", .{sep});
        } else {
            try writer.writer.print("{s}{x:02}", .{ sep, byte.? });
        }

        sep = if ((i +% 1) & 0xF == 0) "\n         " else if ((i +% 1) & 0x7 == 0) "  " else " ";
    }
    return @ptrCast(writer.written());
}

/// Prints a guide for the memory dump as a C string, stored on buf
fn bufPrintMemoryDumpGuide(buf: []u8, addr: u32) ![:0]u8 {
    @memset(buf, 0);
    var fba = std.heap.FixedBufferAllocator.init(buf);
    var writer = std.Io.Writer.Allocating.init(fba.allocator());
    try writer.writer.writeAll("          0  1  2  3  4  5  6  7   8  9  a  b  c  d  e  f\n");
    try writer.writer.print("{x:08}\n", .{addr});
    try writer.writer.print("{x:08}\n", .{addr + 0x10});
    try writer.writer.print("{x:08}\n", .{addr + 0x20});
    try writer.writer.print("{x:08}\n", .{addr + 0x30});
    try writer.writer.print("{x:08}\n", .{addr + 0x40});
    try writer.writer.print("{x:08}\n", .{addr + 0x50});
    try writer.writer.print("{x:08}\n", .{addr + 0x60});
    try writer.writer.print("{x:08}\n", .{addr + 0x70});
    return @ptrCast(writer.written());
}

fn colorFromInt(int: anytype) rl.Color {
    const c: u32 = @bitCast(int);
    return .{ .r = @truncate(c >> 24), .g = @truncate(c >> 16), .b = @truncate(c >> 8), .a = @truncate(c) };
}

/// Puts all text typed in a frame into the writer. Iff any text was written, returns true.
fn getTypedText(writer: *std.Io.Writer) !bool {
    var k = rl.getKeyPressed();
    if (k == .null) return false;
    while (k != .null) : (k = rl.getKeyPressed()) {
        std.debug.print("{any}\n", .{k});
        switch (@intFromEnum(k)) {
            0...255 => {
                const ch: u8 = @intCast(@intFromEnum(k));
                switch (ch) {
                    'A'...'Z' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte(ch);
                        } else {
                            try writer.writeByte(ch - 'A' + 'a');
                        }
                    },
                    '0' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte(')');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '1' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('!');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '2' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('@');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '3' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('#');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '4' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('$');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '5' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('%');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '6' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('^');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '7' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('&');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '8' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('*');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '9' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('(');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '\'' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('"');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    ',' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('<');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '-' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('_');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '.' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('>');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '/' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('?');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    ';' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte(':');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '=' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('+');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '[' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('{');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '\\' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('|');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    ']' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('}');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    '`' => {
                        if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                            try writer.writeByte('~');
                        } else {
                            try writer.writeByte(ch);
                        }
                    },
                    else => {
                        try writer.writeByte(ch);
                    },
                }
            },
            @intFromEnum(rl.KeyboardKey.enter) => {
                try writer.writeByte('\n');
            },
            @intFromEnum(rl.KeyboardKey.tab) => {
                try writer.writeByte('\t');
            },
            @intFromEnum(rl.KeyboardKey.backspace) => {
                try writer.writeByte(0x08);
            },
            else => {},
        }
    }
    return true;
}
