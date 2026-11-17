# tempus_sta.tcl - signoff static timing on the routed netlist + SPEF
#   cd asic/cadence && tempus -files tempus_sta.tcl -log logs/tempus
source tech_setup.tcl
file mkdir reports/tempus

read_lib     -max $LIB_SLOW -min $LIB_FAST
read_verilog outputs/${DESIGN}_pnr.v
set_top_module $DESIGN
read_sdc     $SDC_FILE
read_spef    outputs/${DESIGN}.spef

set_analysis_mode -analysisType onChipVariation -cppr both
update_timing -full

report_timing -late  -max_paths 20 > reports/tempus/setup.rpt
report_timing -early -max_paths 20 > reports/tempus/hold.rpt
report_constraint -all_violators   > reports/tempus/violators.rpt
report_analysis_summary            > reports/tempus/summary.rpt
