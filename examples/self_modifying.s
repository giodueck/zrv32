    lui t0, %hi(0x00100073)
    addi t0, t0, %lo(0x00100073)
    auipc t1, 0
    sw t0, 12(t1)
    fence.i     # Flush instruction pipeline and load next instruction again
    nop         # <- this instruction becomes ebreak (0x00100073)
    nop         # Bus must allow writing this section of memory for this to work
    nop
    nop
    nop
    nop
    nop
    nop
    ebreak
