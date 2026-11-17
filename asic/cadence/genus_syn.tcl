# genus_syn.tcl - logic synthesis of rv32_core with Cadence Genus
#   cd asic/cadence && genus -files genus_syn.tcl -log logs/genus
# Outputs: outputs/rv32_core_syn.v (netlist), .sdc, .sdf, LEC dofile; reports/*.rpt
source tech_setup.tcl
file mkdir outputs reports logs

set_db information_level 7
set_db init_hdl_search_path $RTL_DIR
set_db library    [list $LIB_SLOW]
set_db lef_library $LEF_FILES
if {[file exists $QRC_TECH]} { set_db qrc_tech_file $QRC_TECH }

# ---------------------------------------------------------------- read + elaborate
read_hdl -sv $RTL_FILES
elaborate $DESIGN
check_design -unresolved
check_design -all > reports/check_design.rpt

read_sdc $SDC_FILE
report_timing -lint > reports/timing_lint.rpt

# ---------------------------------------------------------------- synthesis
set_db syn_generic_effort medium
set_db syn_map_effort     high
set_db syn_opt_effort     high

syn_generic
report_timing > reports/timing_generic.rpt
syn_map
report_timing > reports/timing_map.rpt
syn_opt

# ---------------------------------------------------------------- reports
report_qor                       > reports/qor.rpt
report_area                      > reports/area.rpt
report_gates                     > reports/gates.rpt
report_timing -max_paths 10      > reports/timing.rpt
report_power                     > reports/power.rpt
report_clock_gating              > reports/clock_gating.rpt
report_messages                  > reports/messages.rpt

# ---------------------------------------------------------------- outputs
write_hdl > outputs/${DESIGN}_syn.v
write_sdc > outputs/${DESIGN}_syn.sdc
write_sdf -timescale ns -nonegchecks -recrem split -edges check_edge \
          -setuphold split > outputs/${DESIGN}_syn.sdf
write_do_lec -revised_design outputs/${DESIGN}_syn.v \
             -logfile logs/lec_rtl2syn.log > outputs/lec_rtl2syn.do

puts "Genus done: [get_db current_design .name] -> outputs/${DESIGN}_syn.v"
