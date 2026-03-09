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

The emulator will run until an EBREAK is run, at which point the CPU state is printed to stderr. For example, the program `add_sub.s`:
```assembly
    addi x10, x0, 0x123
    addi x11, x0, 0x555

    addi x12, x10, 0x765
    add x13, x10, x11
    sub x14, x11, x10

    addi x10, x10, 1
    addi x10, x10, 1
    addi x10, x10, -1
    addi x10, x10, -1

    ebreak
```

Will produce the following output:
```
$ ./zig-out/bin/zrv32 out.bin
Warning: No program binary loaded

pc: 0x00001034
zero ( x0) 0x00000000 |   ra ( x1) 0x00000000
  sp ( x2) 0x00000000 |   gp ( x3) 0x00000000
  tp ( x4) 0x00000000 |   t0 ( x5) 0x00000000
  t1 ( x6) 0x00000000 |   t2 ( x7) 0x00000000
  s0 ( x8) 0x00000000 |   s1 ( x9) 0x00000000
  a0 (x10) 0x00000123 |   a1 (x11) 0x00000555
  a2 (x12) 0x00000888 |   a3 (x13) 0x00000678
  a4 (x14) 0x00000432 |   a5 (x15) 0x00000000
  a6 (x16) 0x00000000 |   a7 (x17) 0x00000000
  s2 (x18) 0x00000000 |   s3 (x19) 0x00000000
  s4 (x20) 0x00000000 |   s5 (x21) 0x00000000
  s6 (x22) 0x00000000 |   s7 (x23) 0x00000000
  s8 (x24) 0x00000000 |   s9 (x25) 0x00000000
 s10 (x26) 0x00000000 |  s11 (x27) 0x00000000
  t3 (x28) 0x00000000 |   t4 (x29) 0x00000000
  t5 (x30) 0x00000000 |   t6 (x31) 0x00000000
```

### Creating programs
Programs can be compiled with the `riscv32-unknown-elf-*` toolchain. The necessary commands to create the bare binary from assembly source are wrapped in the `assembleboot.sh` and `assembleprog.sh` scripts. The difference between them is only the base address used, but it is crucial for each type of binary (boot and program).

This script then produces an ELF and a binary .bin file:
```bash
$ ./assembleboot.sh source.s out
$ ls
. .. <other files> assembleboot.sh source.s out out.bin
```
