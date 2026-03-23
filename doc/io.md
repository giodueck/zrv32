# Input/Output in the Emulator

Risc-V uses memory mapped I/O, which means all input and output must go through memory instructions.

The implemented devices in this emulator are the following:
- Character device

## Character output device
This is a simple text output device which prints bytes to the terminal.

Any store to this location causes the least-significant byte to be printed to the output.

Any load is ignored.

The address to write bytes to is set by the Bus implementation.

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

## Character input device
***TODO** implement*

Similar to the output device, but instead, it is only meant to be read from. It consists of a queue in which only the first item is exposed on MMIO.

Any load to this location reads one byte from the queue. All valid characters are zero-extended bytes. If the queue is empty, a load will result in a word-length -1.

Any store is ignored.

The address to read from and the length of the queue are set by the Bus implementation.

When interrupts are implemented, a non-empty queue or a full queue may trigger interrupts.

## Block device storage
***TODO** implement*

This is a device which can be read from and written to in blocks. Its size is variable and it provides several registers to interface with it:

- block size register (word ro): stores the block size to read and write. Any access to the device will be of this size. Is guaranteed to be a power of 2.
- data registers (bytes rw): a group of registers to read into or write out of the block device. The number of registers is the same as the block device, and the address of the first must be aligned to the block size.
- seek register (word rw): this controls where in the block device the next read will access, and this address must be block size aligned. Read or write access to the disk causes this register to be incremented by the block size.
- read register (word wo): storing any value here causes the data registers to be set to the data at the seek position in the block device. The value stored is discarded.
- write register (word wo): storing any value here causes the block at the seek position to be set to the data registers in the block device. The value stored is discarded.

If a custom instruction to copy a large block of memory from one memory section to another is implemented, it must support the data registers in this device as well.

The addresses at which these registers are found is set by the Bus implementation, as is the block size.

## Display device
***TODO** implement*

This is a 24-bit color screen with double buffering. One buffer is internal and holds the active pixels, while the other is memory mapped. The registers provided are:

- resolution register (word ro): holds the screen dimensions in two halfwords. The most significant halfword holds the width, while the least significant halfword holds the height: i.e. a word looks like `WWWW HHHH`
- push frame register (word wo): storing any value here causes the screen buffer to be overwritten by the MMIO buffer registers. The value stored is discarded.
- buffer registers (words rw): a group of registers to write into the screen buffer. The number of registers is `W*H` (times 4 as each pixel is a word), with `W` and `H` being the width and height stored in the resolution register.

The buffer registers are organized in an array of arrays, with `H` elements of `W` words. The first word is at screen coordinate (0,0) at the top left of the screen. A coordinate (x,y) is calculated to be at the address A: `A <- (y * W + x) * 4`.

Alpha blending is a feature that may be implemented on top of these specs, but might be better left for a version 2.
