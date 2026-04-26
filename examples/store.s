    la a0, 0x80000000

    li t0, 0x87654321

    sw t0, 0(a0)
    sh t0, 4(a0)
    sb t0, 8(a0)

    lw a1, 0(a0)
    lw a2, 4(a0)
    lw a3, 8(a0)

    ebreak
