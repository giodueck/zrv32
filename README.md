# zrv32
Simple Risc-V 32-bit computer emulator

## Motivation
The idea is to build a simple RV32I VM to build a better understanding of the architecture.

If this project goes well and the idea seems plausible, I plan to implement the same machine in (simulated) hardware
in Factorio's Circuit Network.

## Goals
- [ ] RV32I: base integer (unprivileged) instruction set
- [ ] Instruction pipeline: fetch, decode, read registers, execute, memory access (possibly combined with execute), writeback
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
