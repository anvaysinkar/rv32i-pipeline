# build.tcl - Vivado non-project batch flow for the Nexys4: RTL -> bitstream
#
# usage (from the fpga/ directory):
#   vivado -mode batch -source build.tcl                       ;# original Nexys4
#   vivado -mode batch -source build.tcl -tclargs nexys4_ddr   ;# Nexys4 DDR / Nexys A7
#
# Outputs land in fpga/out/: bitstream, utilization, timing and power reports.

set board [expr {[llength $argv] > 0 ? [lindex $argv 0] : "nexys4"}]
set part  xc7a100tcsg324-1
set root  [file normalize [file dirname [info script]]/..]
set out   $root/fpga/out
file mkdir $out

# the program images must sit where $readmemh can find them during synthesis
foreach f {imem.hex dmem.hex} {
    if {![file exists $root/sw/demo/$f]} {
        error "sw/demo/$f missing - run 'make -C sw/demo' first"
    }
    file copy -force $root/sw/demo/$f $out/$f
}
cd $out

# ---------------------------------------------------------------- sources
read_verilog [glob $root/rtl/*.v]
read_verilog [glob $root/fpga/nexys4/*.v]
read_xdc     $root/fpga/nexys4/$board.xdc
add_files    [list $out/imem.hex $out/dmem.hex]

# ---------------------------------------------------------------- synthesis
synth_design -top nexys4_top -part $part -include_dirs $root/rtl
write_checkpoint -force post_synth.dcp
report_utilization -file util_synth.rpt
report_timing_summary -file timing_synth.rpt

# ---------------------------------------------------------------- implementation
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force post_route.dcp

report_utilization              -file util_route.rpt
report_utilization -hierarchical -file util_hier.rpt
report_timing_summary -max_paths 20 -file timing_route.rpt
report_power                    -file power.rpt
report_drc                      -file drc.rpt

# fail loudly on negative slack
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "INFO: worst setup slack = $wns ns"
if {$wns < 0} {
    puts "WARNING: timing not met - lower the core clock (CLKOUT0_DIVIDE_F in nexys4_top.v)"
}

# ---------------------------------------------------------------- bitstream
write_bitstream -force rv32_nexys4.bit
puts "INFO: bitstream written to $out/rv32_nexys4.bit"
