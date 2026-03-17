# TODO

## Base RV32I

- [x] Register-Immediate
    - [x] addi
    - [x] slti[u]
    - [x] andi, ori, xori
    - [x] slli, srli, srai
    - [x] lui
    - [x] auipc
- [x] Register-Register
    - [x] add, sub
    - [x] slt[u]
    - [x] and, or, xor
    - [x] sll, srl, sra
- [x] Pseudo-instructions
    - [x] nop
    - [x] mv
    - [x] seqz
    - [x] snez
- [x] Control transfer
    - [x] Unconditional jumps
    - [x] Conditional branching
- [x] Load and Store
    - [x] lw, lh, lb, lhu, lbu
    - [x] sw, sh, sb
- [x] Memory ordering
    this is just a NOP
- [x] Environment call and Breakpoints
    - [x] ebreak
    - [x] priv
    - [x] zicsr

## Extensions

- [x] Zicsr extension (and machine/user mode privilege)
- [x] Zifencei extension
- [x] M extension

## Interactive emulator

- [x] Run program
- [x] Step through program
- [x] Reset CPU
- [x] Intuitive controls
- [ ] Memory inspector
- [ ] GUI for more flexible control over input and output

## Architecture

- [x] Generic Bus interface (to have different possible environments, e.g. riscv-test with _start at 0x8000_0000)
- [ ] Dynamically allocated memory, only allocated when written to.
- [ ] Actual memory mapped timer accessible via `mtime` address and `time` CSRs
- [ ] Interrupts

## Input/Output

- [x] Text output
- [ ] Text input
- [ ] Color screen
- [ ] Block device (storage device)
