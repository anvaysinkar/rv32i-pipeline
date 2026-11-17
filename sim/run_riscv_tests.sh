#!/usr/bin/env bash
# run_riscv_tests.sh - build every rv32ui test and run it on the RTL with Icarus.
#
# Needs: riscv64-unknown-elf-gcc (or riscv32-...), iverilog, python3, git
# usage: sim/run_riscv_tests.sh [test ...]      (default: all supported rv32ui tests)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=$ROOT/sim/build
TESTS_REPO=${RISCV_TESTS:-$BUILD/riscv-tests}
PREFIX=${CROSS:-riscv64-unknown-elf-}

mkdir -p "$BUILD"
if [ ! -d "$TESTS_REPO/isa" ]; then
    git clone --depth 1 https://github.com/riscv-software-src/riscv-tests.git "$TESTS_REPO"
fi

# compile the RTL once
iverilog -g2012 -I "$ROOT/rtl" -o "$BUILD/tb_soc.vvp" \
    "$ROOT"/rtl/*.v "$ROOT/sim/tb_soc.v"

# fence_i needs self-modifying code (impossible with a separate IMEM),
# ma_data needs misaligned-access traps; both are outside this core's scope.
if [ $# -gt 0 ]; then
    LIST="$*"
else
    LIST=$(ls "$TESTS_REPO/isa/rv32ui/"*.S | xargs -n1 basename | sed 's/\.S$//' \
           | grep -v -E '^(fence_i|ma_data)$')
fi

pass=0; fail=0; failed=""
for t in $LIST; do
    d=$BUILD/$t; mkdir -p "$d"
    "${PREFIX}gcc" -march=rv32i -mabi=ilp32 -static -nostdlib -nostartfiles \
        -I "$ROOT/sw/tests/env" -I "$TESTS_REPO/isa/macros/scalar" \
        -T "$ROOT/sw/link.ld" -o "$d/$t.elf" "$TESTS_REPO/isa/rv32ui/$t.S"
    "${PREFIX}objcopy" -O binary -j .text "$d/$t.elf" "$d/imem.bin"
    "${PREFIX}objcopy" -O binary -j .data "$d/$t.elf" "$d/dmem.bin"
    python3 "$ROOT/sw/elf2hex.py" "$d/imem.bin" "$d/imem.hex"
    python3 "$ROOT/sw/elf2hex.py" "$d/dmem.bin" "$d/dmem.hex"
    res=$(cd "$d" && vvp -n "$BUILD/tb_soc.vvp" | grep -E 'PASS|FAIL|TIMEOUT' || true)
    printf '%-8s %s\n' "$t" "$res"
    if [[ $res == PASS* ]]; then pass=$((pass+1)); else fail=$((fail+1)); failed="$failed $t"; fi
done

echo "----------------------------------------"
echo "passed: $pass   failed: $fail${failed:+  ($failed )}"
[ $fail -eq 0 ]
