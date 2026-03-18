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

    // const state_view_title = "Current Hart State";
    // const logical_state_view_title = "Logical Hart State";
    // const output_view_title = "Output";

    // Real hart state output
    var state_str = try hart.allocPrintState(allocator);
    var state_cstr: [:0]u8 = try allocator.dupeZ(u8, state_str);
    defer allocator.free(state_str);
    defer allocator.free(state_cstr);

    // Text output writer
    var raw_output_writer = std.io.Writer.Allocating.init(allocator);
    defer raw_output_writer.deinit();
    hart.bus.setCharDevWriter(&raw_output_writer.writer);

    const font = try rl.loadFontFromMemory(".ttf", hack_ttf, 16, &charset);
    defer rl.unloadFont(font);

    rl.setTargetFPS(60); // Set our game to run at 60 frames-per-second
    rl.setExitKey(.null); // Unset ESC as the default exit key
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) {

        // Update
        //----------------------------------------------------------------------------------
        // Input
        var step = false;
        var reset = false;
        if (rl.isKeyPressed(.s) or rl.isKeyPressedRepeat(.s)) {
            step = true;
        }
        if (rl.isKeyPressed(.r)) {
            reset = true;
        }

        // Run emulator
        var update_outputs = false;
        if (step and !hart.ebreak and hart.fatal_exception == null) {
            hart.step();
            update_outputs = true;
        } else if (reset) {
            hart.reset();
            update_outputs = true;
        }

        // Update outputs
        if (update_outputs) {
            allocator.free(state_str);
            allocator.free(state_cstr);
            state_str = try hart.allocPrintState(allocator);
            state_cstr = try allocator.dupeZ(u8, state_str);
        }
        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.init(20, 20, 50, 255));

        rl.drawTextEx(font, state_cstr, .{ .x = 10, .y = 10 }, 16, 0, .light_gray);
        //----------------------------------------------------------------------------------
    }
}
