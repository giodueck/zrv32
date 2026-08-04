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
    - [ ] Misaligned instruction address exception generated at branch
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
        - [ ] Backspace handling
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
- [x] Text input
- [ ] Color screen
- [ ] Block device (storage device)

## Performance optimization targets

- [x] RAM (hash map accesses are slow): replaced with a sparse array, which is what was needed anyways.
- [ ] standardBus.load (13% of the runtime at ~490KHz)
- [ ] Hart.step (13% of the runtime at ~490KHz)

## Custom instructions

For eventual implementation in Factorio, two custom instructions would be good to have:

- [ ] pow, powi: integer exponentiation, `pow/i rd, rs1, rs2/imm12` does `rd <- rs1^(rs2/imm12)`, where `^` is the power operator. R and I types.
- [ ] bml\[a-h], bms\[a-h]: bulk memory access, load/store a block of registers to/from a memory address. The addresses must be aligned to a predefined block size. This instruction is defined in detail in instructions.md.

Both instructions may be implemented to run in very short times. The first can be implemented in a single combinator with a built-in function. The second uses the fact that dense memory in Factorio is implemented as an array of memory cells, each holding many 32-bit signals, which means a wipe and rewrite of all signals at once is even simpler than just accessing one of those signals. E.g. a memory cell holding 64 32-bit signals spans 256 bytes in address space, which then defines 256 as the block size for bulk memory access.
