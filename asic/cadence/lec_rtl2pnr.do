// lec_rtl2pnr.do - Conformal LEC: RTL vs. placed-and-routed netlist
//   cd asic/cadence && lec -XL -nogui -dofile lec_rtl2pnr.do
// (Genus also writes outputs/lec_rtl2syn.do for RTL vs. synthesis netlist.)
// Edit the .lib path to match tech_setup.tcl.

set log file logs/lec_rtl2pnr.log -replace

read library -liberty -both ~/pdk/gsclib045_all_v4.4/gsclib045/timing/slow_vdd1v0_basicCells.lib

read design -verilog -golden -include ../../rtl \
    ../../rtl/rv32_alu.v ../../rtl/rv32_regfile.v ../../rtl/rv32_decoder.v ../../rtl/rv32_core.v
read design -verilog -revised outputs/rv32_core_pnr.v

set root module rv32_core -both
set system mode lec
add compared points -all
compare

report verification
report unmapped points -summary
report compare data -class nonequivalent

exit -force
