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
- [x] GUI for more flexible control over input and output
    - [x] Register view
    - [x] Text output view
        - [x] Wrapping text
        - [x] Scrolling
        - [ ] ANSI escape sequences
    - [x] Help screen
    - [x] Mode indicator (step, running, halted)
    - [x] Variable emulator speed
    - [x] Memory inspector
        - [x] Address selection controls
        - [x] Address display help on top and left of data
    - [x] Switch to Raygui

## Architecture

- [x] Generic Bus interface (to have different possible environments, e.g. riscv-test with _start at 0x8000_0000)
- [x] Dynamically allocated memory, only allocated when written to.
- [x] Actual memory mapped timer accessible via `mtime` address and `time` CSRs
- [ ] Interrupts

## Input/Output

- [x] Text output
- [ ] Text input
- [ ] Color screen
- [ ] Block device (storage device)

## Performance optimization targets

- [x] RAM (hash map accesses are slow): replaced with a sparse array, which is what was needed anyways.
- [ ] standardBus.load (13% of the runtime at ~490KHz)
- [ ] Hart.step (13% of the runtime at ~490KHz)
