const std = @import("std");

const rl = @import("raylib");

const Hart = @import("hart.zig").Hart;
const riscv = @import("riscv.zig");

const keybinds = [_][]const u8{
    "<s> Step 1 cycle",
    "<S> Step many cycles",
    "<R> Reset hart",
    "<q> Exit",
};

const hack_ttf = @embedFile("resources/Hack-Regular.ttf");
const charset = a: {
    const chars = "!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
    var i32chars = [_]i32{0} ** chars.len;
    for (chars, 0..) |c, i| {
        i32chars[i] = c;
    }
    break :a i32chars;
};

pub fn guiMain(allocator: std.mem.Allocator, hart: *Hart) !void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 600;

    rl.initWindow(screenWidth, screenHeight, "zrv32");
    defer rl.closeWindow(); // Close window and OpenGL context

    var show_logical_state = true;

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

    // Use a monospaced font instead of the default
    const font = try rl.loadFontFromMemory(".ttf", hack_ttf, 16, &charset);
    defer rl.unloadFont(font);
    const font_height = 18;
    const font_width = 8;

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    rl.setExitKey(.null); // Unset ESC as the default exit key
    //--------------------------------------------------------------------------------------

    // Main game loop
    var run = false;
    const run_steps = 16;
    while (!rl.windowShouldClose()) {

        // Update
        //----------------------------------------------------------------------------------
        // Input
        var step = false;
        var reset = false;
        var update_outputs = false;
        if (rl.isKeyPressed(.s) or rl.isKeyPressedRepeat(.s)) {
            if (rl.isKeyDown(.left_shift) or rl.isKeyDown(.right_shift)) {
                run = !run;
            }
            step = true;
        }
        if (rl.isKeyPressed(.r)) {
            reset = true;
        }
        if (rl.isKeyPressed(.t)) {
            show_logical_state = !show_logical_state;
            update_outputs = true;
        }

        // Run emulator
        if (hart.ebreak or hart.fatal_exception != null) {
            run = false;
            step = false;
            halted = true;
        }
        if (run) {
            for (0..run_steps) |_| {
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
        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.init(20, 20, 50, 255));

        const text_offset = rl.Vector2.init(10, 10);

        // Draw hart state
        const state_size = rl.Vector2.init(48, 29);
        rl.drawRectangleRoundedLines(rl.Rectangle.init(text_offset.x, text_offset.y - 4, font_width * state_size.x, font_height * state_size.y + 4), 0.05, 4, .sky_blue);

        if (show_logical_state) {
            rl.drawTextEx(font, logical_state_title, text_offset.add(.{ .x = 2 * font_width, .y = 0 }), 16, 0, .blue);

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
                rl.drawRectangleRounded(.{ .x = @floatFromInt(@as(i32, @intFromFloat(text_offset.x)) + column * font_width - 1), .y = @floatFromInt(@as(i32, @intFromFloat(text_offset.y)) + line * font_height - 1), .width = @floatFromInt(font_width * @as(i32, @intCast(logical_state_str.hi_end - logical_state_str.hi_begin)) + 2), .height = @floatFromInt(font_height) }, 0.2, 2, .dark_blue);
            }
            rl.drawTextEx(font, logical_state_cstr, text_offset.add(.{ .x = font_width, .y = font_height }), 16, 0, .light_gray);

            rl.drawTextEx(font, csr_state_cstr, text_offset.add(.{ .x = font_width, .y = font_height * 18 }), 16, 0, .light_gray);
        } else {
            rl.drawTextEx(font, state_title, text_offset.add(.{ .x = 2 * font_width, .y = 0 }), 16, 0, .yellow);
            rl.drawTextEx(font, state_cstr, text_offset.add(.{ .x = font_width, .y = font_height }), 16, 0, .light_gray);
        }

        // Draw text output
        const text_output_size = rl.Vector2.init(48, 29);
        rl.drawRectangleRoundedLines(rl.Rectangle.init(text_offset.x + font_width * state_size.x, text_offset.y - 4, font_width * text_output_size.x, font_height * text_output_size.y + 4), 0.05, 4, .sky_blue);

        const text_output_offset = text_offset.add(state_size.multiply(.{ .x = font_width, .y = 0 }));
        rl.drawTextEx(font, text_output_title, text_output_offset.add(.{ .x = 2 * font_width, .y = 0 }), 16, 0, .blue);

        rl.drawTextEx(font, text_output_cstr, text_output_offset.add(.{ .x = 1 * font_width, .y = 1 * font_height }), 16, 0, .light_gray);
        //----------------------------------------------------------------------------------
    }
}
