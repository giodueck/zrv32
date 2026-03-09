# Trap implementation

The trap controller can be run in parallel to the writeback stage.

When a trap is triggered, the trap controller stores the address of the instruction currently in the execute stage into a special register, sets PC to the handler stub address and invalidates/flushes the pipeline (including the instruction currently in execute, where any traps generated in this step are ignored).

The x1 register is transparently switched to a trap register, separate from the normal version so as to not clobber the value inside it, and the address of the instruction following the trap is placed into it. The end of the trap is a return instruction, which switches the registers back.

The hart has a flag to indicate that it is inside a trap.

This way, invisible traps can be implemented for various purposes and ecalls can be implemented in a simple fashion. The table of locations to jump to for trap handlers is hardcoded to a place inside the boot binary. The boot binary must then look like the following:

```assembly
    j _start

    j trap_handler_1
    j trap_handler_2
    j trap_handler_3
    ...

_start:
    # main program
    ebreak

trap_handler_1:
    nop
    ret

trap_handler_2:
    nop
    ret

trap_handler_3:
    nop
    ret
```

That is: the 0 address must jump to the actual start, any following addresses must jump to the corresponding trap handler, up to some maximum number of handlers. If any trap is handled by ignoring or halting, insert a nop or ebreak instead.

## Traps

1. Instruction Access Fault: address at PC is not executable
2. Illegal Instruction: invalid or unimplemented instruction
3. Breakpoint: ebreak
4. Load Access Misaligned
5. Load Access Fault: address not readable
6. Store Access Misaligned
7. Store Access Fault: address not writable
8. Environment Call: ecall
9. to 15. reserved

Some of these may be implemented as invisible traps, like misaligned store or load.

Breakpoint will interrupt the core and halt, waiting for user input.
