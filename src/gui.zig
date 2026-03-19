const std = @import("std");

const rl = @import("raylib");

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
        .screen = .help,
        .keys = &.{ rl.KeyboardKey.h, rl.KeyboardKey.escape },
        .description = "Hide this help screen",
    },
};

pub fn guiMain(allocator: std.mem.Allocator, hart: *Hart) !void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 600;

    rl.initWindow(screenWidth, screenHeight, "zrv32");
    defer rl.closeWindow(); // Close window and OpenGL context

    // Colors used in drawing
    const title_color: rl.Color = .blue;
    const text_color: rl.Color = .light_gray;
    const secondary_text_color: rl.Color = .gray;
    const highlight_color: rl.Color = .dark_blue;
    const border_color: rl.Color = .sky_blue;
    const keybind_color: rl.Color = .purple;
    const semaphore_colors: [3]rl.Color = [_]rl.Color{ .red, .yellow, .green };

    // Section titles
    const state_title = "Real Hart State";
    const logical_state_title = "Logical Hart State";
    const text_output_title = "Output";

    // Real hart state
    var state_str = try hart.allocPrintState(allocator);
    var state_cstr: [:0]u8 = try allocator.dupeZ(u8, state_str);
    defer allocator.free(state_str);
    defer allocator.free(state_cstr);

    // Logical hart state
    var logical_state_str = try hart.allocPrintLogicalState(allocator);
    var logical_state_cstr: [:0]u8 = try allocator.dupeZ(u8, logical_state_str.slice);
    defer logical_state_str.deinit();
    defer allocator.free(logical_state_cstr);

    // Standalone CSR and priv state, which is not appended to the logical state
    var csr_state_str = try hart.allocPrintCSRs(allocator);
    var csr_state_cstr: [:0]u8 = try allocator.dupeZ(u8, csr_state_str);
    defer allocator.free(csr_state_str);
    defer allocator.free(csr_state_cstr);

    // Text output writer
    var text_output_writer = std.io.Writer.Allocating.init(allocator);
    defer text_output_writer.deinit();
    hart.bus.setCharDevWriter(&text_output_writer.writer);
    var text_output_cstr = try allocator.dupeZ(u8, text_output_writer.written());
    defer allocator.free(text_output_cstr);

    // General purpose text buffer
    const gp_buffer = try allocator.allocSentinel(u8, 1024, 0);
    defer allocator.free(gp_buffer);

    // Use a monospaced font instead of the default
    const font = try rl.loadFontFromMemory(".ttf", hack_ttf, 16, &charset);
    defer rl.unloadFont(font);
    const font_height = 18;
    const font_width = 8;

    const title_font = try rl.loadFontFromMemory(".ttf", hack_ttf, 20, &charset);
    defer rl.unloadFont(title_font);

    const target_fps = 60;
    rl.setTargetFPS(target_fps); // Set our game to run at 60 frames-per-second
    rl.setExitKey(.null); // Unset ESC as the default exit key
    //--------------------------------------------------------------------------------------

    // Main loop variables
    var current_screen: Screen = .state;

    // State screen variables
    var show_logical_state = true;
    var run = false;
    var run_steps: u32 = 16; // Steps per frame
    var halted = false;
    var step_indicator: u32 = 0; // For indicating the emulator is running for a few frames if only a step was taken
    const step_indicator_count = 5;

    // Main loop
    while (!rl.windowShouldClose()) {
        defer step_indicator -|= 1;

        // Update
        //----------------------------------------------------------------------------------
        var step = false;
        var reset = false;
        var update_outputs = false;

        switch (current_screen) {
            .state => {
                if (rl.isKeyPressed(.s) or rl.isKeyPressedRepeat(.s)) {
                    if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                        run = !run;
                    }
                    step = true;
                    step_indicator = step_indicator_count;
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
                if (rl.isKeyPressed(.h)) {
                    current_screen = .help;
                    step = false;
                    reset = false;
                    run = false;
                }

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
                    update_outputs = true;
                    halted = false;
                }

                // Update outputs
                if (update_outputs) {
                    if (show_logical_state) {
                        logical_state_str.deinit();
                        allocator.free(logical_state_cstr);
                        logical_state_str = try hart.allocPrintLogicalState(allocator);
                        logical_state_cstr = try allocator.dupeZ(u8, logical_state_str.slice);

                        allocator.free(csr_state_str);
                        allocator.free(csr_state_cstr);
                        csr_state_str = try hart.allocPrintCSRs(allocator);
                        csr_state_cstr = try allocator.dupeZ(u8, csr_state_str);
                    } else {
                        allocator.free(state_str);
                        allocator.free(state_cstr);
                        state_str = try hart.allocPrintState(allocator);
                        state_cstr = try allocator.dupeZ(u8, state_str);
                    }
                    allocator.free(text_output_cstr);
                    text_output_cstr = try allocator.dupeZ(u8, text_output_writer.written());
                }
            },
            .help => {
                if (rl.isKeyPressed(.h) or rl.isKeyPressed(.escape)) {
                    current_screen = .state;
                }
            },
        }
        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.init(20, 20, 50, 255));

        switch (current_screen) {
            .state => {
                const text_offset = rl.Vector2.init(10, 14);

                // Draw hart state
                const state_size = rl.Vector2.init(48, 29);
                rl.drawRectangleRoundedLines(rl.Rectangle.init(text_offset.x, text_offset.y - 4, font_width * state_size.x, font_height * state_size.y + 4), 0.05, 4, border_color);

                // Hart frequency
                const freq_cstr = try std.fmt.bufPrintZ(gp_buffer, "{d} Hz", .{@as(u64, run_steps) * target_fps});
                rl.drawTextEx(font, freq_cstr, text_offset.add(.{ .x = (state_size.x - 3) * font_width - @as(f32, @floatFromInt(freq_cstr.len * font_width)), .y = 0 }), 16, 0, semaphore_colors[2]);

                // Running indicator
                rl.drawCircle(@as(i32, @intFromFloat(text_offset.x)) + @as(i32, @intFromFloat(state_size.x - 2)) * font_width + @divTrunc(font_width, 2), @as(i32, @intFromFloat(text_offset.y)) + @divTrunc(font_height, 2), 8, if (halted) semaphore_colors[0] else if (run or step_indicator > 0) semaphore_colors[2] else semaphore_colors[1]);

                if (show_logical_state) {
                    rl.drawTextEx(font, logical_state_title, text_offset.add(.{ .x = 2 * font_width, .y = 0 }), 16, 0, title_color);

                    if (logical_state_str.hi_end > logical_state_str.hi_begin) {
                        // This text has highlight information
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
                        rl.drawRectangleRounded(.{ .x = @floatFromInt(@as(i32, @intFromFloat(text_offset.x)) + column * font_width - 1), .y = @floatFromInt(@as(i32, @intFromFloat(text_offset.y)) + line * font_height - 1), .width = @floatFromInt(font_width * @as(i32, @intCast(logical_state_str.hi_end - logical_state_str.hi_begin)) + 2), .height = @floatFromInt(font_height) }, 0.2, 2, highlight_color);
                    }
                    rl.drawTextEx(font, logical_state_cstr, text_offset.add(.{ .x = font_width, .y = font_height }), 16, 0, text_color);

                    rl.drawTextEx(font, csr_state_cstr, text_offset.add(.{ .x = font_width, .y = font_height * 18 }), 16, 0, text_color);
                } else {
                    // Real hart state
                    rl.drawTextEx(font, state_title, text_offset.add(.{ .x = 2 * font_width, .y = 0 }), 16, 0, title_color);
                    rl.drawTextEx(font, state_cstr, text_offset.add(.{ .x = font_width, .y = font_height }), 16, 0, text_color);
                }

                // Draw text output
                const text_output_size = rl.Vector2.init(48, 29);
                const text_output_offset = text_offset.add(state_size.multiply(.{ .x = font_width, .y = 0 })).add(.{ .x = font_width, .y = 0 });
                rl.drawRectangleRoundedLines(rl.Rectangle.init(text_output_offset.x, text_output_offset.y - 4, font_width * text_output_size.x, font_height * text_output_size.y + 4), 0.05, 4, border_color);

                rl.drawTextEx(font, text_output_title, text_output_offset.add(.{ .x = 2 * font_width, .y = 0 }), 16, 0, title_color);

                rl.drawTextEx(font, text_output_cstr, text_output_offset.add(.{ .x = 1 * font_width, .y = 1 * font_height }), 16, 0, text_color);

                // Draw help hint
                rl.drawTextEx(font, "Press ", text_offset.add(state_size.multiply(.{ .x = 0, .y = font_height })).add(.{ .x = 0, .y = font_height }), 16, 0, secondary_text_color);
                rl.drawTextEx(font, "h", text_offset.add(state_size.multiply(.{ .x = 0, .y = font_height })).add(.{ .x = font_width * 6, .y = font_height }), 16, 0, keybind_color);
                rl.drawTextEx(font, " for help", text_offset.add(state_size.multiply(.{ .x = 0, .y = font_height })).add(.{ .x = font_width * 7, .y = font_height }), 16, 0, secondary_text_color);
            },

            .help => {
                const text_offset = rl.Vector2.init(10, 14);
                const help_size = rl.Vector2.init(97, 29);
                rl.drawRectangleRoundedLines(rl.Rectangle.init(text_offset.x, text_offset.y - 4, font_width * help_size.x, font_height * help_size.y + 4), 0.035, 4, border_color);

                rl.drawTextEx(font, "Keybind help", text_offset.add(.{ .x = 2 * font_width, .y = 0 }), 16, 0, title_color);

                // Show all keybinds for each screen
                var line: i32 = 1;
                inline for (@typeInfo(Screen).@"enum".fields) |s| {
                    rl.drawTextEx(font, comptime if (s.value == @intFromEnum(Screen.state)) "Emulator" else if (s.value == @intFromEnum(Screen.help)) "Keybind help", text_offset.add(.{ .x = font_width, .y = @floatFromInt(line * font_height) }), 16, 0, title_color);
                    line += 1;

                    for (Keybinds) |bind| {
                        if (@intFromEnum(bind.screen) == s.value) {
                            var offset: i32 = 0;
                            for (bind.keys, 0..) |key, i| {
                                if (i > 0) {
                                    rl.drawTextEx(font, ", ", text_offset.add(.{ .x = @floatFromInt((2 + offset) * font_width), .y = @floatFromInt(line * font_height) }), 16, 0, keybind_color);
                                    offset += 2;
                                }
                                for (bind.mods) |mod| {
                                    rl.drawTextEx(font, @tagName(mod), text_offset.add(.{ .x = @floatFromInt((2 + offset) * font_width), .y = @floatFromInt(line * font_height) }), 16, 0, keybind_color);
                                    offset += @intCast(@tagName(mod).len);
                                    rl.drawTextEx(font, " + ", text_offset.add(.{ .x = @floatFromInt((2 + offset) * font_width), .y = @floatFromInt(line * font_height) }), 16, 0, keybind_color);
                                    offset += 3;
                                }

                                rl.drawTextEx(font, getKeyName(key), text_offset.add(.{ .x = @floatFromInt((2 + offset) * font_width), .y = @floatFromInt(line * font_height) }), 16, 0, keybind_color);
                                offset += @intCast(getKeyName(key).len);
                            }
                            rl.drawTextEx(font, ": ", text_offset.add(.{ .x = @floatFromInt((2 + offset) * font_width), .y = @floatFromInt(line * font_height) }), 16, 0, text_color);
                            offset += 2;

                            rl.drawTextEx(font, bind.description, text_offset.add(.{ .x = @floatFromInt((2 + offset) * font_width), .y = @floatFromInt(line * font_height) }), 16, 0, text_color);
                            line += 1;
                        }
                    }
                }
            },
        }
        //----------------------------------------------------------------------------------
    }
}

// Some keys don't have a name and cause assertion failures
fn getKeyName(key: rl.KeyboardKey) [:0]const u8 {
    return switch (key) {
        .escape => return "Escape",
        else => rl.getKeyName(key),
    };
}
