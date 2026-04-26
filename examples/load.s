    la a0, array

    lw a1, 0(a0)
    lw a2, 4(a0)

    lhu a3, 0(a0)
    lhu a4, 2(a0)
    lh a5, 4(a0)
    lh a6, 6(a0)

    lbu a7, 6(a0)
    lbu s2, 7(a0)
    lb s3, 6(a0)
    lb s4, 7(a0)

    ebreak

array:
    .word 0x12345678, 0x87654321
