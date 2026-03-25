/* Basic OS

    This OS hands off control to the program at 0x80000000 in User mode.
    There is no address access control enforced by the OS, so any memory
    management must be done by the User program.

    Upon entering a syscall, the registers are saved on the stack, so all
    of them are preserved, even the temporary ones. In this way, syscalls
    behave transparently for the caller.

    The following syscalls are available:
    1. exit: stops the emulator
    2. putc: print a single character
    3. puts: print a 0 terminated string
    4. nputs: print a 0 terminated string or n characters
    5. getc: read a single character from input. If input is empty, returns -1
*/

.equ mtime, 0x100
.equ outchardev, 0x200
.equ inchardev, 0x204
.equ initialsp, 0xC0000000

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

    # OS main

    # Set sp to end of RAM section. It will grow downwards
    lui sp, %hi(initialsp)
    addi sp, sp, %lo(initialsp)

    # Reserve 256 bytes for OS stack
    # User stack starts 256 bytes lower
    addi t2, sp, -256

    la t0, handler
    csrw mtvec, t0

    # Registers are saved in a struct:
    # struct regs {
    #    uint32_t pc;
    #    uint32_t ra; // x1
    #    uint32_t sp; // x2
    #    ...
    #    uint32_t t6; // x31
    # };

    # Prepare struct regs
    addi sp, sp, -128

    mv a0, sp # struct regs *

    # Set user pc
    la t0, 0x80000000
    sw t0, 0(a0)

    # Set user sp
    sw t2, 8(a0)

    j enter_user


# void trap_main(struct regs *);
trap_main:
    # Save registers
    addi sp, sp, -16
    sw s0, 0(sp)
    sw ra, 4(sp)

    mv s0, a0
    csrr a1, mcause
    li t1, 8 # Environment call from User mode
    bne a1, t1, bad_exception

    lw a0, 40(s0)
    lw a1, 44(s0)
    lw a2, 48(s0)
    lw a3, 52(s0)
    lw a4, 56(s0)
    lw a5, 60(s0)
    lw a6, 64(s0)
    lw a7, 68(s0)
    call syscall

    # User return value
    sw a0, 40(s0)

    # Bump user pc by 4 to skip over ecall
    lw t0, 0(s0)
    addi t0, t0, 4
    sw t0, 0(s0)

    # Restore registers
    lw ra, 4(sp)
    lw s0, 0(sp)
    addi sp, sp, 16
    ret

# a0-a6 = args, a7 = syscall number
syscall:
    li t0, 1
    beq a7, t0, sys_exit
    li t0, 2
    beq a7, t0, sys_putc
    li t0, 3
    beq a7, t0, sys_puts
    li t0, 4
    beq a7, t0, sys_nputs
    li t0, 5
    beq a7, t0, sys_getc

    li a0, -1
    ret

# Stop the emulator
# [[noreturn]] void sys_exit();
sys_exit:
    ebreak

# Print a single character
# void putc(char);
sys_putc:
    addi sp, sp, -8
    sw ra, 0(sp)

    call kputc
    li a0, 0

    lw ra, 0(sp)
    addi sp, sp, 8

    ret

# Print a 0 terminated strings
# void puts(const char *);
sys_puts:
    addi sp, sp, -8
    sw ra, 0(sp)

    call kputs
    li a0, 0

    lw ra, 0(sp)
    addi sp, sp, 8

    ret

# Print a 0 terminated strings untile either a 0 is encountered or n characters are printed
# void puts(const char *, int);
sys_nputs:
    addi sp, sp, -8
    sw ra, 0(sp)

    call knputs
    li a0, 0

    lw ra, 0(sp)
    addi sp, sp, 8

    ret

# Read a single character from input. If the input is empty, the returned value is -1
# int getc();
sys_getc:
    addi sp, sp, -8
    sw ra, 0(sp)

    call kgetc

    lw ra, 0(sp)
    addi sp, sp, 8

    ret

# Print message about bad exception, then stop the emulator
# [[noreturn]] void bad_exception(struct regs *, int cause)
bad_exception:
    mv s0, a1
    la a0, msg_exception
    call kputs

    la t0, hex_chars
    andi t1, s0, 0xf
    add t2, t0, t1
    lb a0, 0(t2)
    call kputc
    srli s0, s0, 4
    add t2, t0, t1
    lb a0, 0(t2)
    call kputc

    li a0, 0x0a # '\n'
    call kputc

    ebreak

fatal:
    la a0, msg_fatal
    call kputs
    ebreak

msg_fatal:
    padded_string "Fatal exception\n", 20

msg_exception:
    padded_string "Exception 0x", 20

hex_chars:
    padded_string "0123456789abcdef", 16

# Print string by accessing MMIO character device.
# void kputs(const char *);
kputs:
    la t1, outchardev
1:
    lb t0, 0(a0)
    beq t0, zero, 2f
    sw t0, 0(t1)
    addi a0, a0, 1
    j 1b
2:
    ret


# Print string by accessing MMIO character device.
# void knputs(const char *, int);
knputs:
    la t1, outchardev
    li t0, 0
1:
    beq t0, a0, 2f
    lb t0, 0(a0)
    beq t0, zero, 2f
    sw t0, 0(t1)
    addi a0, a0, 1
    addi t0, t0, 1
    j 1b
2:
    ret


# Print character by accessing MMIO character output device.
# void kputc(char);
kputc:
    la t1, outchardev
    sw a0, 0(t1)
    ret


# Get a single character from MMIO character input device. If the input is empty, reads -1.
# int kgetc();
kgetc:
    la t1, inchardev
    lw a0, 0(t1)
    ret


handler:
    csrrw sp, mscratch, sp

    # If mscratch was 0, this is exception from M-mode
    # Can't handle that, it's a fatal error
    beq sp, zero, fatal

    # Save all registers
    addi sp, sp, -128
    sw x1, 4(sp)
    # x2/sp handled separately
    sw x3, 12(sp)
    sw x4, 16(sp)
    sw x5, 20(sp)
    sw x6, 24(sp)
    sw x7, 28(sp)
    sw x8, 32(sp)
    sw x9, 36(sp)
    sw x10, 40(sp)
    sw x11, 44(sp)
    sw x12, 48(sp)
    sw x13, 52(sp)
    sw x14, 56(sp)
    sw x15, 60(sp)
    sw x16, 64(sp)
    sw x17, 68(sp)
    sw x18, 72(sp)
    sw x19, 76(sp)
    sw x20, 80(sp)
    sw x21, 84(sp)
    sw x22, 88(sp)
    sw x23, 92(sp)
    sw x24, 96(sp)
    sw x25, 100(sp)
    sw x26, 104(sp)
    sw x27, 108(sp)
    sw x28, 112(sp)
    sw x29, 116(sp)
    sw x30, 120(sp)
    sw x31, 124(sp)

    # Save user sp, also set mscratch to 0 in M-mode
    csrrw t0, mscratch, zero
    sw t0, 8(sp)

    # Save user pc
    csrr t0, mepc
    sw t0, 0(sp)

    mv a0, sp
    call trap_main
    # ... falls through after trap_main ...
enter_user:
    # Set mstatus.mpp = User
    lui t0, %hi(0x1800)
    addi t0, t0, %lo(0x1800)
    csrrc zero, mstatus, t0

    # Set mepc = user pc
    # We will jump there with mret
    lw t0, 0(sp)
    csrw mepc, t0

    # Set mscratch to user sp
    # We will swap before mret
    lw t0, 8(sp)
    csrw mscratch, t0

    # Restore other registers from stack
    lw x1, 4(sp)
    # sp handled separately
    lw x2, 8(sp)
    lw x3, 12(sp)
    lw x4, 16(sp)
    lw x5, 20(sp)
    lw x6, 24(sp)
    lw x7, 28(sp)
    lw x8, 32(sp)
    lw x9, 36(sp)
    lw x10, 40(sp)
    lw x11, 44(sp)
    lw x12, 48(sp)
    lw x13, 52(sp)
    lw x14, 56(sp)
    lw x15, 60(sp)
    lw x16, 64(sp)
    lw x17, 68(sp)
    lw x18, 72(sp)
    lw x19, 76(sp)
    lw x20, 80(sp)
    lw x21, 84(sp)
    lw x22, 88(sp)
    lw x23, 92(sp)
    lw x24, 96(sp)
    lw x25, 100(sp)
    lw x26, 104(sp)
    lw x27, 108(sp)
    lw x28, 112(sp)
    lw x29, 116(sp)
    lw x30, 120(sp)
    lw x31, 124(sp)
    addi sp, sp, 128

    # Enter user mode
    csrrw sp, mscratch, sp
    mret
