    la t0, handler
    csrw mtvec, t0

    # Now cause an exception
    csrw cycle, x0

    # Rest of the main program is never executed
    addi a0, a0, 1
    addi a0, a0, 1

handler:
    la a0, msg
    call puts
    ebreak

msg:
    .byte 0x4f, 0x68, 0x20, 0x6e, 0x6f, 0x21, 0x0a, 0x00

    # void puts(const char *);
puts:
    lui t1, %hi(0x00010000)
1:
    lb t0, 0(a0)
    beq t0, zero, 2f
    sw t0, 0(t1)
    addi a0, a0, 1
    j 1b

2:
    ret

