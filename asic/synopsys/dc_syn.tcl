# dc_syn.tcl - logic synthesis of rv32_core with Synopsys Design Compiler
#   cd asic/synopsys && dc_shell -f dc_syn.tcl | tee logs/dc.log
source tech_setup.tcl
file mkdir outputs reports logs work

define_design_lib WORK -path ./work
set_app_var search_path   [concat . $RTL_DIR $search_path]
set_app_var target_library $DB_SLOW
set_app_var link_library   [concat * $DB_SLOW]

# guidance file for Formality (records renaming/optimisations)
set_svf outputs/${DESIGN}.svf

# ---------------------------------------------------------------- read + elaborate
analyze -format verilog $RTL_FILES
elaborate $DESIGN
current_design $DESIGN
link
check_design > reports/check_design.rpt
uniquify

# ---------------------------------------------------------------- constraints
source $SDC_FILE
check_timing > reports/check_timing.rpt

# ---------------------------------------------------------------- compile
set_fix_multiple_port_nets -all -buffer_constants
compile_ultra -no_autoungroup
optimize_netlist -area

# ---------------------------------------------------------------- reports
report_qor                              > reports/qor.rpt
report_area -hierarchy                  > reports/area.rpt
report_timing -max_paths 10 -nets -transition_time > reports/timing.rpt
report_constraint -all_violators        > reports/violators.rpt
report_power                            > reports/power.rpt
report_reference -hierarchy             > reports/references.rpt

# ---------------------------------------------------------------- outputs
change_names -rules verilog -hierarchy
write -format verilog -hierarchy -output outputs/${DESIGN}_syn.v
write -format ddc     -hierarchy -output outputs/${DESIGN}_syn.ddc
write_sdc  outputs/${DESIGN}_syn.sdc
write_sdf  outputs/${DESIGN}_syn.sdf
set_svf -off

exit
