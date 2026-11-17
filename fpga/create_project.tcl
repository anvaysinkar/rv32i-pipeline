# create_project.tcl - build a Vivado GUI project for the Nexys4
#
# Vivado Tcl console (Tools -> Run Tcl Script) or:
#   vivado -mode batch -source create_project.tcl                      ;# Nexys4
#   vivado -mode batch -source create_project.tcl -tclargs nexys4_ddr  ;# Nexys4 DDR
# then open fpga/vivado_proj/rv32_nexys4.xpr in the GUI.

set board [expr {[llength $argv] > 0 ? [lindex $argv 0] : "nexys4"}]
set root  [file normalize [file dirname [info script]]/..]
set proj  $root/fpga/vivado_proj

create_project rv32_nexys4 $proj -part xc7a100tcsg324-1 -force
set_property target_language Verilog [current_project]

add_files -norecurse [glob $root/rtl/*.v $root/rtl/*.vh $root/fpga/nexys4/*.v]
set_property file_type {Verilog Header} [get_files *.vh]
set_property include_dirs $root/rtl [current_fileset]

# program images (Vivado resolves $readmemh paths relative to the source set)
add_files -norecurse [list $root/sw/demo/imem.hex $root/sw/demo/dmem.hex]
set_property file_type {Memory Initialization Files} [get_files *.hex]

add_files -fileset constrs_1 -norecurse $root/fpga/nexys4/$board.xdc
set_property top nexys4_top [current_fileset]

# simulation: core-level ISA testbench and board-level demo testbench
add_files -fileset sim_1 -norecurse [list $root/sim/tb_soc.v $root/sim/tb_nexys4_top.v]
set_property top tb_nexys4_top [get_filesets sim_1]
set_property verilog_define {SIM} [get_filesets sim_1]
set_property include_dirs $root/rtl [get_filesets sim_1]

puts "INFO: project created at $proj/rv32_nexys4.xpr"
