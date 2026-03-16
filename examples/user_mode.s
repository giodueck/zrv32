    la t0, handler
    csrw mtvec, t0

    lui t0, %hi(0x1800)
    addi t0, t0, %lo(0x1800)

    # Clear MPP to 0
    csrrc zero, mstatus, t0

    la t0, user_entry
    csrw mepc, t0
    mret

handler:
    ebreak # Just stop the emulator

user_entry:
    ebreak
    # ecall
    # unimp

