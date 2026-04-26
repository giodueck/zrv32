# Risc-V example assembly programs

These examples were mostly taken from the excelent [Easy Risc-V](https://easyriscv.dram.page/#intentionally-causing-an-exception) page by [dramforever](https://github.com/dramforever) and adapted to this emulator. Some concepts were also taken from there, like halting the emulator on M-Mode `ebreak`.

Compile these examples with the `riscv32-unknown-elf-*` toolchain or the helper script `assembleboot.sh`, then run the resulting .bin file with the emulator.

The examples cover a range of the RV32I_Zicsr_Zifencei instruction set:

- `arithmetic.s`: basic arithmetic instructions
- `largeFDimmediate.s`: loading 32-bit immediate values
- `comparisons.s`: basic integer comparisons translated to assembly
- `sum_1_to_100.s`: branching and loops
- `load.s`: loads
- `store.s`: stores
- `memory_access.s`: load and store (will not work with a read-only executable section, only for demonstration)
- `sum_array.s`: load and store in a loop
- `function_call.s`: implementing function calls and returns
- `fib_recursive.s`: recursive calls and use of the stack
- `hello_world_basic.s`, `hello_world_basic.s`: use of memory mapped I/O devices
- `exception_handling.s`, `user_mode.s`: exception handling, CSR instructions and privilege modes
- `self_modifying.s`: self modifying code relying on Zifencei to work (will not work with a read-only executable section, only for demonstration)
- `bare_bones_os.s`: entry point into an M-Mode OS with U-Mode code, complete with system calls and User exception handling

## Developed

`boot/` and `program/` contain hand-crafted programs that are more complex than the simple examples. They contain programs to be loaded as boot and program binaries, respectively
