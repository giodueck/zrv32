# zrv32
Simple Risc-V 32-bit computer emulator

## Motivation
The idea is to build a simple RV32I VM to build a better understanding of the architecture.

If this project goes well and the idea seems plausible, I plan to implement the same machine in (simulated) hardware
in Factorio's Circuit Network.

## Goals
- [x] RV32I: base integer (unprivileged) instruction set
- [x] 5-Stage Instruction pipeline: fetch, decode, read registers, execute and memory access, writeback
- [ ] M: integer multiplication and division

Potential goals: Run Linux on the emulated CPU; add Factorio-specific extensions
- [ ] Exceptions, interrupts and traps
- [ ] Zifencei: Instruction-Fetch fence
- [ ] A: Atomic operations
- [ ] Zicsr: Control Status Register operations
- [ ] Zicntr: extension for counters
- [ ] F: Accurate FPU emulation (the IEEE standard used is newer than x86_64)
- [ ] Privileged ISA
- [ ] Additional extensions for special operations (power for Factorio)

## Building
Standard Zig build commands:

- Build: `zig build`
- Build and run: `zig build run`
- Build and run (with arguments): `zig build run -- [arguments]`
- Test: `zig build test`

## Running
Build artifacts land in `zig-out/bin`.

Run with `-h` or `--help` to get a help menu.

To run a binary boot ROM program, run `./zig-out/bin/zrv32 boot.bin`.

To also add a program ROM (a separate larger ROM from boot ROM), add another positional argument: `./zig-out/bin/zrv32 boot.bin program.bin`.

### Creating programs
Programs can be compiled with the `riscv32-unknown-elf-*` toolchain. The necessary commands to create the bare binary from assembly source are wrapped in the `assemble.sh` script.

This script then produces an ELF and a binary .bin file:
```bash
$ ./assemble.sh source.s out
$ ls
. .. <other files> assemble.sh source.s out out.bin
```
