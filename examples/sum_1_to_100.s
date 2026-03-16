    li x10, 100         # i = 100
    li x11, 0           # sum = 0

loop:
    add x11, x11, x10   # sum = sum + i
    addi x10, x10, -1   # i = i - 1
    blt x0, x10, loop   # If i > 0: loop again
                        # Otherwise: done

    ebreak

