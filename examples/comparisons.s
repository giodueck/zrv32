    li x10, 0x3
    li x11, 0x5

    slt x12, x10, x11   # x10 < x11
    slt x13, x11, x10   # x10 > x11

    xori x14, x12, 1    # x10 >= x11  i.e.  !(x10 < x11)
    xori x15, x13, 1    # x10 <= x11  i.e.  !(x10 > x11)

    ebreak

