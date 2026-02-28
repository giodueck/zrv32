# Instructions
These are the instructions to implement, summarized from the ISA specs at https://docs.riscv.org/reference/isa/_attachments/riscv-unprivileged.pdf

## Instruction formats
RV32I contains 4 base instruction formats: R,I,S,U. All are 32 bits in length.

All instructions must be aligned to 4 bytes for the base instruction set. When branching to an unaligned
address, an exception is generated on the branch instruction. If the branch is not taken, the exception is not
generated either. *Consider how or if this will be implemented.*

The 4 base instruction formats are:

R-Type:
```
31          25 24     20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│   funct7    │   rs2   │   rs1   │     │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
                                   funct3
```

I-Type:
```
31                    20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│        imm[11:0]      │   rs1   │     │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
                                   funct3
```

S-Type:
```
31          25 24     20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│  imm[11:5]  │   rs2   │   rs1   │     │imm[4:0] │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
                                   funct3
```

U-Type:
```
31                                    12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│             imm[31:12]                │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
```

### Immediate encoding variants
A further 2 encodings exist based on the handling of immediates: B,J. They are based on the S and U encodings.

B-Type:
```
31 30       25 24     20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│ │ imm[10:5] │   rs2   │   rs1   │     │       │ │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
[12]                             funct3 imm[4:1] [11]
```

J-Type:
```
31 30              21 20 19           12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│ │     imm[10:1]     │ │  imm[19:12]   │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
[20]                  [11]
```

### Immediate types
The different immediate values generated with immediate encodings. Sign extension is always done with
`inst[31]`.

I-Immediate:
```
31                                      11 10        5 4     1 0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│                --inst[31]--             │inst[30:25]│[24:21]│ │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
                                                              [20]
```

S-Immediate:
```
31                                      11 10        5 4     1 0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│                --inst[31]--             │inst[30:25]│[11:8] │ │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
                                                              [7]
```

B-Immediate:
```
31                                   12 11 10        5 4     1 0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│                --inst[31]--           │ │inst[30:25]│[11:8] │0│
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
                                        [7]
```

U-Immediate:
```
31 30                 20 19           12 11                    0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│ │     inst[30:20]     │  inst[19:12]  │          0            │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
[31]
```

J-Immediate:
```
31                    20 19          12 11 10        5 4     1 0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│       --inst[31]--    │  inst[19:12]  │ │inst[30:25]│[24:21]│0│
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
                                        [20]
```

## Base integer instructions

### Integer computational

#### Integer Register-Immediate Instructions

I-Type:
```
31                    20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│        imm[11:0]      │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
            12               5       3       5           7
    I-Immediate[11:0]     src   ADDI/SLTI[U]  dest     OP-IMM
    I-Immediate[11:0]     src  ANDI/ORI/XORI  dest     OP-IMM
```

I-Type:
```
31          25 24     20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│  imm[11:5]  │imm[4:0] │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
      7            5         5       3       5           7
 0 0 0 0 0 0 0 shamt[4:0] src      SLLI    dest        OP-IMM
 0 0 0 0 0 0 0 shamt[4:0] src      SRLI    dest        OP-IMM
 0 1 0 0 0 0 0 shamt[4:0] src      SRAI    dest        OP-IMM
```

U-Type:
```
31                                    12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│             imm[31:12]                │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
                   20                        5           7
            U-Immediate[31:12]             dest         LUI
            U-Immediate[31:12]             dest        AUIPC
```

#### Integer Register-Register Instructions

R-Type:
```
31          25 24     20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│   funct7    │   rs2   │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
      7            5         5       3       5           7
 0 0 0 0 0 0 0    src1   src2   ADD/SLT[U]  dest        OP
 0 0 0 0 0 0 0    src1   src2   AND/OR/XOR  dest        OP
 0 0 0 0 0 0 0    src1   src2     SLL/SRL   dest        OP
 0 1 0 0 0 0 0    src1   src2     SUB/SRA   dest        OP
```

#### NOP Instruction

NOP is encoded as `ADDI x0, x0, 0`.

I-Type:
```
31                    20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│        imm[11:0]      │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
            12               5       3       5           7
            0                0      ADDI     0         OP-IMM
```

### Control Transfer Instructions

#### Unconditional Jumps

Plain unconditional jumps are encoded as JAL with rd=x0.

J-Type:
```
31 30              21 20 19           12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│ │     imm[10:1]     │ │  imm[19:12]   │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
[20]                  [11]
 1         10          1       8             5           7
        offset[20:1]                        dest        JAL
```

I-Type:
```
31                    20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│        imm[11:0]      │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
            12               5       3       5           7
         offset[11:0]       base     0      dest        JALR
```

#### Conditional Branches

B-Type:
```
31          25 24     20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│imm[12|10:5] │   rs2   │   rs1   │ f3  │         │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
                                       imm[4:1|11]
       7           5         5       3       5           7
offset[12|10:5]   src2      src1  BEQ/BNE offset[4:1|11] BRANCH
offset[12|10:5]   src2      src1  BLT[U]  offset[4:1|11] BRANCH
offset[12|10:5]   src2      src1  BGE[U]  offset[4:1|11] BRANCH
```

### Load and Store Instructions

I-Type:
```
31                    20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│        imm[11:0]      │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
            12               5       3       5           7
        offset[11:0]        base   width    dest        LOAD
```

S-Type:
```
31          25 24     20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│  imm[11:5]  │   rs2   │   rs1   │ f3  │imm[4:0] │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
       7           5         5       3       5           7
offset[11:5]      src       base   width  offset[4:0]  STORE
```

### Memory Ordering Instructions

I-Type:
```
31                    20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│  fm   │ │ │ │ │ │ │ │ │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
    4    1 1 1 1 1 1 1 1     5       3       5           7
   FM    P P P P S S S S     0     FENCE     0        MISC-MEM
         I O R W I O R W
```

### Environment Call and Breakpoints

I-Type:
```
31                    20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│        imm[11:0]      │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
            12               5       3       5           7
           ECALL             0      PRIV     0         SYSTEM
          EBREAK             0      PRIV     0         SYSTEM
```

### HINT Instructions

Most effectively-NOP instructions are reserved for use as hints to the microarchitecture. These can safely be ingnored
or treated as regular instructions.

## M Extension for integer multiplication and division

### Multiplication Operations

R-Type:
```
31          25 24     20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│   funct7    │   rs2   │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
       7           5         5       3       5           7
     MULDIV   multiplier       MUL/MULH[[S]U]           OP
                        multiplicand       dest
```

### Division Operations

R-Type:
```
31          25 24     20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│   funct7    │   rs2   │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
       7           5         5       3       5           7
     MULDIV    divisor          DIV[U]/REM[U]           OP
                        dividend           dest
```

## B Extension for bit manipulation

Consider implementing:
- Zbb for basic bit manipulation instructions.
- Zbc for carryless multiplication.
- Zbs for single bit operations

TODO add table of opcodes
