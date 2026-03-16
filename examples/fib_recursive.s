    lui sp, %hi(0x00050000)     # Set sp to end of RAM section. It will grow downwards
    addi sp, sp, %lo(0x00050000)
    li a0, 10
    jal fib
    ebreak

fib:
    li t0, 2

    # If n < 2, then return n
    bge a0, t0, fib_large
    ret

fib_large:
    # Otherwise, n >= 2

    # Save stuff to stack
    addi sp, sp, -16
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)

    mv s0, a0       # s0 = n
    addi a0, a0, -1 # a0 = n - 1

    jal fib
    mv s1, a0       # s1 = fib(n - 1)

    addi a0, s0, -2
    jal fib         # fib(n - 2)

    add a0, a0, s1

    # Restore stuff from stack and return
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    addi sp, sp, 16
    ret

