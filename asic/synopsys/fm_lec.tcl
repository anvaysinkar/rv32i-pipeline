# fm_lec.tcl - Formality equivalence check: RTL vs. synthesised netlist
#   cd asic/synopsys && fm_shell -f fm_lec.tcl | tee logs/fm.log
# Swap outputs/rv32_core_syn.v for outputs/rv32_core_pnr.v to check the routed netlist.
source tech_setup.tcl

set_svf outputs/${DESIGN}.svf
read_db $DB_SLOW

read_verilog -r $RTL_FILES -libname WORK
set_top r:/WORK/$DESIGN

read_verilog -i outputs/${DESIGN}_syn.v -libname WORK
set_top i:/WORK/$DESIGN

match
if {![verify]} {
    report_failing_points > reports/fm_failing.rpt
    analyze_points -failing > reports/fm_analyze.rpt
}
report_status
exit
