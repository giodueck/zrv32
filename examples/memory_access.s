    lui x10, %hi(foo)
    lw x11, %lo(foo)(x10)

    li x12, 0x123
    sw x12, %lo(foo)(x10)

    # Now it's changed
    lw x13, %lo(foo)(x10)
    ebreak

foo:
    .word 0xf00

