#!/usr/bin/env bash
# run_board_sim.sh - simulate the whole Nexys4 top (MMCM bypassed) running the demo
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD=$ROOT/sim/build/board
mkdir -p "$BUILD"

make -s -C "$ROOT/sw/demo" clean all CFLAGS_EXTRA=-DCORE_HZ=4000
cp "$ROOT/sw/demo/imem.hex" "$ROOT/sw/demo/dmem.hex" "$BUILD/"

iverilog -g2012 -DSIM -I "$ROOT/rtl" -o "$BUILD/tb.vvp" \
    "$ROOT"/rtl/*.v "$ROOT"/fpga/nexys4/*.v "$ROOT/sim/tb_nexys4_top.v"
cd "$BUILD" && vvp -n tb.vvp "$@"

# rebuild the demo at the real clock rate so the hex files are ready for Vivado
make -s -C "$ROOT/sw/demo" clean all
