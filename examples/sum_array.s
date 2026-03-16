    lui x10, %hi(array)
    addi x10, x10, %lo(array)

    li x11, 8   # length

    # Get end address
    slli x11, x11, 2
    add x11, x11, x10

    li x12, 0 # sum

loop:
    # If current == end, done
    beq x10, x11, end
    lw x13, 0(x10)      # Load from array
    add x12, x12, x13   # Add to sum
    addi x10, x10, 4    # Bump current pointer
    j loop

end:
    ebreak


array:
    .word 13, 24, 6, 7, 8, 19, 0, 4
