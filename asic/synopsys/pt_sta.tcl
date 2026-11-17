# pt_sta.tcl - signoff static timing with PrimeTime on the routed netlist
#   cd asic/synopsys && pt_shell -f pt_sta.tcl | tee logs/pt.log
# Use StarRC SPEF if you have it (see GUIDE), otherwise the ICC2 parasitics.
source tech_setup.tcl
file mkdir reports/pt

set_app_var search_path [concat . $search_path]
set_app_var link_path   [concat * $DB_SLOW]

read_verilog outputs/${DESIGN}_pnr.v
current_design $DESIGN
link_design

set spef [lindex [glob -nocomplain outputs/${DESIGN}*.spef* outputs/starrc/*.spef] 0]
if {$spef ne ""} { read_parasitics -format spef $spef } else { puts "WARNING: no SPEF found" }

source $SDC_FILE
set_propagated_clock [all_clocks]
set_app_var timing_remove_clock_reconvergence_pessimism true
update_timing -full

report_global_timing                        > reports/pt/global.rpt
report_timing -delay_type max -max_paths 20 > reports/pt/setup.rpt
report_timing -delay_type min -max_paths 20 > reports/pt/hold.rpt
report_constraint -all_violators            > reports/pt/violators.rpt
report_clock_timing -type skew              > reports/pt/skew.rpt
write_sdf -version 3.0 outputs/${DESIGN}_signoff.sdf
exit
