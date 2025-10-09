const std = @import("std");
const clap = @import("clap");

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator{ .child_allocator = std.heap.page_allocator, .state = .{} };
    defer arena.deinit();
    const allocator = arena.allocator();

    var stderr_buf: [1024]u8 = undefined;
    var stderr_writer = std.fs.File.stderr().writer(&stderr_buf);
    const stderr = &stderr_writer.interface;

    // Parameters the program can take
    const params = [_]clap.Param(u8){
        .{
            .id = 'h',
            .names = .{ .short = 'h', .long = "help" },
        },
    };

    const usage_str =
        "Usage: zrv32 [-h|--help]\n" ++
        "       zrv32 <binary executable>\n";

    const help_str = usage_str ++ "\n" ++
        "<binary executable> is an executable that contains purely Risc-V machine code.\n" ++
        "Unlike regular executable formats, like ELF, it should not contain a header.\n\n" ++
        "Options:\n" ++
        "   -h  --help      Print this help menu and exit\n\n";

    var iter = try std.process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();

    // Skip program name
    _ = iter.next();

    // Initialize diagnostics
    var diag = clap.Diagnostic{};
    var cla_parser = clap.streaming.Clap(u8, std.process.ArgIterator){
        .params = &params,
        .iter = &iter,
        .diagnostic = &diag,
    };

    // We use the streaming parser, so we consume each argument individually
    while (cla_parser.next() catch |err| {
        // Report useful error message and exit
        try diag.report(stderr, err);

        try stderr.writeAll(usage_str);
        try stderr.flush();
        return 1;
    }) |arg| {
        // arg.param will point to the parameter which matched the argument
        switch (arg.param.id) {
            'h' => {
                try stderr.writeAll(help_str);
                try stderr.flush();
                return 0;
            },
            else => unreachable,
        }
    }

    // Free parser resources, but keep the reserved capacity
    _ = arena.reset(.retain_capacity);

    // Command-line argument parsing done
    try stderr.print("Hello\n", .{});
    try stderr.flush();

    // API needs:
    //  - Load program
    //  - Set initial state of CPU
    //  - Run single cycle of CPU (advance each pipeline stage once)
    //  - Run single instruction (not always one cycle, runs until an instruction finishes its last stage and wasn't flushed by a branch)
    //  - By extension:
    //      - Run N cycles
    //      - Run N instructions
    //  - Run until halt (which shouldn't exist on "bare metal" but still, maybe define a set of halting conditions)
    //  - Run until breakpoint
    //
    // Testing needs:
    //  - Initialize at custom state
    //  - Interpret instructions
    //  - Run single instruction

    return 0;
}
