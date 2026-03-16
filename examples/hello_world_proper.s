    lui a0, %hi(msg)
    addi a0, a0, %lo(msg)
    jal puts
    ebreak

    # void puts(const char *);
puts:
    lui t1, %hi(0x00010000)
puts_loop:
    lb t0, 0(a0)
    beq t0, zero, puts_done
    sw t0, 0(t1)
    addi a0, a0, 1
    j puts_loop

puts_done:
    ret

msg:
    .byte 0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x2c, 0x20, 0x77
    .byte 0x6f, 0x72, 0x6c, 0x64, 0x21, 0x0a, 0x00

