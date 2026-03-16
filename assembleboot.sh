#!/bin/sh
set -e

SOURCE=$1
OUTNAME=$2

if [ $# -lt 2 ]; then
    echo "Want at least 2 arguments: SOURCE and OUTNAME"
    exit 1
fi

riscv32-unknown-elf-as --march=rv32im_zifencei_zicsr $SOURCE -o $OUTNAME.o
riscv32-unknown-elf-ld -Ttext=0x1000 $OUTNAME.o -o $OUTNAME
riscv32-unknown-elf-objcopy -O binary $OUTNAME $OUTNAME.bin
