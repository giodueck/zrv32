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

### Trap Return

I-Type:
```
31                    20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│        imm[11:0]      │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
            12               5       3       5           7
           MRET              0      PRIV     0         SYSTEM
```

### Instruction Fence

I-Type:
```
31                    20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│        imm[11:0]      │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
            12               5       3       5           7
            0                0    FENCE.I    0        MISC-MEM
```

### CSR Instructions

I-Type:
```
31                    20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│           csr         │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
            12               5       3       5           7
       source/dest         source  CSRRW    dest       SYSTEM
       source/dest         source  CSRRS    dest       SYSTEM
       source/dest         source  CSRRC    dest       SYSTEM
       source/dest       uimm[4:0] CSRRWI   dest       SYSTEM
       source/dest       uimm[4:0] CSRRSI   dest       SYSTEM
       source/dest       uimm[4:0] CSRRCI   dest       SYSTEM
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

## Custom-0: Integer Exponentiation

This operation behaves as it does in Factorio, limited to a precision of a 32-bit integer.

#### Register-Immediate

I-Type:
```
31                    20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│        imm[11:0]      │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
            12               5       3       5           7
    I-Immediate[11:0]       src      0     dest       CUSTOM-0
```

Performs integer exponentiation with `src` as the base and the immediate value as the exponent.

#### Register-Register

R-Type:
```
31          25 24     20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│   funct7    │   rs2   │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
      7            5         5       3       5           7
 0 0 0 0 0 0 0    src1     src2      0     dest       CUSTOM-0
```

Performs integer exponentiation with `src1` as the base and `src2` as the exponent.

## Custom-1: Bulk Memory Access

Since a hardware register in Factorio is able to hold an arbitrary number of signals in one combinator, this is
the obvious path to take when designing systems with a large amount of memory. However, accessing this memory
involves several steps.

For loading/storing a single value from a multi-value register:
- Decompose the address: the block address (high bits) and the fine address (low bits). The block address refers
  to the hardware register, while the fine address refers to the individual signal inside the register, which is
  ultimately the value that is wanted.
- Load the register contents (the block), using the block address.
- In case of LOAD: Extract and return the desired value using the fine address.
- In case of STORE: Overwrite the target value using the fine address.
- In case of STORE: Write the block back into the register.

A logical extension is to skip the steps involving the fine address and use blocks directly. This is the idea
behind these instructions: to manipulate large amounts of data in memory simultaneously.

In line with the RISC philosophy, two instructions are defined in analogy to LOAD and STORE: BLOAD and BSTORE.

### Differences from LOAD/STORE encodings

#### Width
The available values of `width` are the following:

width | Words | Bytes | Insn suffix
----- | ----- | ----- | -----------
    0 |    16 |   64  | a
    1 |    32 |  128  | b
    2 |    64 |  256  | c
    3 |   128 |  512  | d
    4 |   256 | 1024  | e
    5 |   512 | 2048  | f
    6 |  1024 | 4096  | g
    7 |  2048 | 8192  | h

> [!NOTE]
> The maximum of 2048 words, or 8192 bytes, is due to the design of the memory registers, which hold 2048
> signals in the current implementation. Given that much larger memory transfers are less likely, this
> maximum makes sense.
>
> If an implementation uses memory cells which are smaller, it must nonetheless support these sizes of
> access, and may take additional time to do so. For example, an implementation with 1024-word registers may
> take 2 cycles to complete a 2048-word access.

#### Addresses

One additional restriction of these instructions is that all accesses must be 8192-byte-aligned, so as to make
the implementation simpler.

For this reason the actual memory address is not used directly. Instead, the value of `base + offset` is truncated
by 13 bits to be 8192-byte aligned.

In practice, this leaves the immediate offset fields mostly useless, since they cannot address 13 bits by themselves. *Immediate fields should thus be regarded as reserved and set to 0*.

#### Bulk registers

A new type of register is defined for use with this instruction: the bulk register. It is composed of 2048 32-bit
words, just like memory cells.

They are addressed 0-31 just like regular registers, but they instead refer to bulk registers. The register 0 is
hard-wired 0, just like the regular zero register.

A minimum of 3 bulk registers must be implemented, mapped to r1-r3, with any additional ones being optional. This
allows for bulk swaps:
```asm
    li a0, addr0
    li a1, addr1
    bmlh r1, a0 ; load 2048 words into bulk r1 from address at a0
    bmlh r2, a1 ; load 2048 words into bulk r2 from address at a1
    bmsh r1, a1 ; store 2048 words from bulk r1 into address at a1
    bmsh r2, a0 ; store 2048 words from bulk r2 into address at a0
```

> [!NOTE]
> Detection of optional bulk registers can be done with bulk loads and bulk stores to verify if they copy data.

These registers may be accessible to regular LOAD and STORE instructions as memory addressed registers, the location being defined by the EEI.

### Bulk Load

I-Type:
```
31                    20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│        imm[11:0]      │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
            12               5       3       5           7
             0              base   width    dest      CUSTOM-1
```

### Bulk Store

S-Type:
```
31          25 24     20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│  imm[11:5]  │   rs2   │   rs1   │ f3  │imm[4:0] │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
       7           5         5       3       5           7
                  src       base   width     0         CUSTOM-1
```

