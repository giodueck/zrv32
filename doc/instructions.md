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

## Custom-0: Expanded integer operations

Mainly considered for the integer exponentiation operation, which is natively supported in Factorio.

### Integer exponentiation

This operation behaves as it does in Factorio, limited to the precision of a signed 32-bit integer.

#### Register-Immediate

I-Type:
```
31                    20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│        imm[11:0]      │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
            12               5       3       5           7
    I-Immediate[11:0]       src    IPOWI   dest       CUSTOM-0
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
 0 0 0 0 0 0 0    src1     src2    IPOW    dest       CUSTOM-0
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

### Addresses

One additional detail of these instructions is that all accesses must be 8192-byte-aligned, as the memory
registers are. For this reason the actual memory address is not used directly. Instead, the lower 13 bits
of `address` are masked out to be 8192-byte aligned.

Effectively, rs1 is used to index a memory register instead of as a byte address.

### Destination/Source: Bulk registers

The rd field of the instruction refers to a special type of register, called a bulk register.

Bulk registers addressed 0-31 just like regular registers. The register 0 is hard-wired 0, and not all 31
possible registers must be implemented.

The zero bulk register may be used for fast zeroing of memory.

A minimum of 3 bulk registers must be implemented, mapped to r1-r3, with any additional ones being optional.
This allows for bulk swaps, without needing an additional instruction.
```asm
    li a0, addr0
    li a1, addr1
    bulk.load r1, a0, 0 ; load 2048 words into bulk r1 from address at a0
    bulk.load r2, a1, 0 ; load 2048 words into bulk r2 from address at a1
    bulk.store r1, a1, 0 ; store 2048 words from bulk r1 into address at a1
    bulk.store r2, a0, 0 ; store 2048 words from bulk r2 into address at a0
```

> [!NOTE]
> Detection of optional bulk registers can be done with bulk loads and bulk stores to verify if they copy data.

These registers must be accessible to regular LOAD and STORE instructions as memory addressed registers, the
location being defined by the EEI.

### Bulk load and bulk store

I-type:
```
31          25 24     20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│i[11:8]│   imm[7:0]    │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
    4           8            5       3       5           7
  mode        mask        address  BLOAD   b.dest     CUSTOM-1
  mode        mask        address  BSTORE  b.src      CUSTOM-1
```

The possible values for funct3 are:

Value | Name
----- | ------
    0 | BLOAD
    1 | BSTORE

The instruction operates with the fundamental memory registers, which store 8192 bytes in 2048 32-bit words.
This space may be more usefully accessed if it is partitioned into smaller sectors. These sectors may be
selected via the mask, where a 1 enables loading from/storing to the corresponding sector.

The possible values for mode are:

Value | Name     | Description
----- | -------- | -----------
    0 | ALL      | 8KiB, mask is ignored
    1 | LOW8     | 16 512B sectors. imm\[7:0\] select sectors 0..7
    2 | HIGH8    | 16 512B sectors. imm\[7:0\] select sectors 15..8
 3-15 | RESERVED | -

The mask bits are interpreted differently based on the mode. The 8KiB registers are effectively split into
16 sectors, and the effective mask is built from the given bits and mode.

Mode  | Mask | Effective mask
----- | ---- | --------------------------------------------------------
ALL   | any  | 0xFFFF, all sectors selected
LOW8  | 0xmm | 0x00mm, high sectors not selected, low sectors masked
HIGH8 | 0xmm | 0xmm00, low sectors not selected, high sectors masked

### Possible expansion

This instruction could become a powerful SIMD instruction, with operations like `bulk.and`, `bulk.or` and
`bulk.xor`. If operating with Factorio's overflow semantics is fine, 32-bit arithmetic operations could also
be done with `bulk.add`, `buld.sub`, `bulk.mul`, etc.

## Custom SYSTEM: Reset

This instruction performs a system reset, and is an M-mode instruction.

I-Type:
```
31                    20 19     15 14 12 11      7 6           0
┌─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┬─┐
│        imm[11:0]      │   rs1   │ f3  │   rd    │    opcode   │
└─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┴─┘
            12               5       3       5           7
           RESET             0      PRIV     0         SYSTEM
```

Here, `RESET` is the immediate 0xFFF. This places this instruction in the designated custom SYSTEM instruction range.
