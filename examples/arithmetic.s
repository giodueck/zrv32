    li x10, 0x5a1
    xori x10, x10, 0xf0
    xori x10, x10, -1

    li x11, 0x5a1
    addi x12, x11, -1
    and x11, x11, x12
    addi x12, x11, -1
    and x11, x11, x12
    addi x12, x11, -1
    and x11, x11, x12

    li x13, 0x5a1
    ori x14, x13, 0xf
    ori x14, x13, 0xff
    ori x14, x13, 0xf0

    ebreak

