    .macro padded_string string, max
1:
    .ascii "\string"
2:
    .iflt \max - (2b - 1b)
    .error "String too long"
    .endif

    .ifgt \max - (2b - 1b)
    .zero \max - (2b - 1b)
    .endif

    .endm

################################################################################

_start:
    li s0, 0
1:
    la a0, msg_hello
    call puts
    addi s0, s0, 1
    j 1b
    call exit

# [[noreturn]] void exit();
exit:
    li a7, 1
    ecall
    # Not supposed to return, just to be safe
    unimp

# Print byte using system call
# void putc(const char *);
putc:
    li a7, 2
    ecall
    ret

# Print string using system call
# void puts(const char *);
puts:
    li a7, 3
    ecall
    ret

msg_hello:
    padded_string "Hello, world! " 20
