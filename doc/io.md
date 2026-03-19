# Input/Output in the Emulator

Risc-V uses memory mapped I/O, which means all input and output must go through memory instructions.

The implemented devices in this emulator are the following:
- Character device

## Character device
This is a simple text output device which prints bytes to the terminal.

The address to write bytes to is 0x10000. Any store to this location causes the least-significant byte to be printed to the output.

For example:
```assembly
    la x11, 0x200
    li x10, 0x48 # 'H'
    sw x10, 0(x11)
    li x10, 0x69 # 'i'
    sw x10, 0(x11)
    li x10, 0x21 # '!'
    sw x10, 0(x11)
    li x10, 0x0a # '\n'
    sw x10, 0(x11)
    ebreak
```
produces:
```
Hi!
```
