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
- [ ] M extension

## Interactive emulator

- [x] Run program
- [x] Step through program
- [ ] Reset CPU
- [ ] Intuitive controls
