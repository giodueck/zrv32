_start:
    li s0, -1
1:
    la a7, 5
    ecall
    beq s0, a0, 1b
    la a7, 2
    ecall
    j 1b
