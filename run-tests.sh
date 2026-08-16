#!/bin/bash

readonly TEST_PATH=./output/share/riscv-tests/isa
readonly REGEX_TEST_FILTER='rv32[um][im]-p-[^.]*$'
readonly TMPDIR=/tmp/riscv-tests

readonly GREEN='\x1B[1;32m'
readonly RED='\x1B[1;31m'
readonly RESET='\x1B[0m'

if [ ! -d $TEST_PATH ]; then
    echo "Error: riscv-tests not installed at $TEST_PATH"
    echo "Steps:"
    echo "  git clone --recursive https://github.com/riscv-software-src/riscv-tests.git"
    echo "  cd riscv-tests"
    echo "  autoconf"
    echo "  ./configure --prefix=\"\$(realpath '../output')\" --with-xlen=32"
    echo "  make"
    echo "  make install"
    echo "  cd .."
    echo
    echo "Note: If the above steps won't work because of some compiler issue, configure with"
    echo "--with-xlen=64 first, then repeat with 32. This will require the"
    echo "riscv64-unknown-elf-* toolchain."
    exit 1
fi

mkdir -p "$TMPDIR"
for test in $(ls $TEST_PATH | grep -e $REGEX_TEST_FILTER); do
    riscv32-unknown-elf-objcopy -O binary "$TEST_PATH/$test" "$TMPDIR/$test.bin"
    printf "%s:\r\t\t\t\t" "$test"
    haltaddr=$(printf "0x%x" $((0x$(riscv32-unknown-elf-readelf "$TEST_PATH/$test" -s | grep " tohost" | xargs | cut -d' ' -f2)+4)))
    # Test if test runs through
    _=$(timeout 2 ./zig-out/bin/zrv32 -t "$TMPDIR/$test.bin" -s --haltaddr="$haltaddr" 2>/dev/null)
    if [ $? -eq 124 ]; then
        printf "${RED}FAIL${RESET}: Timed out\n"
        continue
    fi
    gp=$(./zig-out/bin/zrv32 -t "$TMPDIR/$test.bin" -s --haltaddr="$haltaddr" 2>/dev/null | cut -d"|" -f2 | grep -m1 -e 'gp' | cut -d")" -f2 | xargs)
    # If nothing was output, the test must have crashed the emulator
    if [ -z "$gp" ]; then
        printf "${RED}FAIL${RESET}: Crashed\n"
        continue
    fi
    a0=$(./zig-out/bin/zrv32 -t "$TMPDIR/$test.bin" -s --haltaddr="$haltaddr" 2>/dev/null | cut -d"|" -f1 | grep -m1 -e 'a0' | cut -d")" -f2 | xargs)
    if [ "$gp" != "0x00000001" ] || [ "$a0" != "0x00000000" ]; then
        printf "${RED}FAIL${RESET}: gp = $gp, a0 = $a0\n"
    else
        printf "${GREEN}PASS${RESET}\n"
    fi
done

rm -rf "$TMPDIR"
