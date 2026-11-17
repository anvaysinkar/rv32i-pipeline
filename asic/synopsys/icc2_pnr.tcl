# icc2_pnr.tcl - floorplan, power, place, CTS, route and GDSII with IC Compiler II
#   cd asic/synopsys && icc2_shell -f icc2_pnr.tcl | tee logs/icc2.log
# Run dc_syn.tcl first.
source tech_setup.tcl
file mkdir outputs reports logs

# ================================================================ 1. design library + netlist
if {[file exists ${DESIGN}.nlib]} { file delete -force ${DESIGN}.nlib }
create_lib ${DESIGN}.nlib -technology $TECH_TF -ref_libs [list $REF_NDM]
read_verilog -top $DESIGN outputs/${DESIGN}_syn.v
link_block

# ================================================================ 2. timing setup (MCMM)
read_parasitic_tech -tlup $TLUP_MAX -layermap $TLUP_MAP -name maxTLU
read_parasitic_tech -tlup $TLUP_MIN -layermap $TLUP_MAP -name minTLU

remove_scenarios -all ; remove_modes -all ; remove_corners -all
create_mode   func
create_corner slow
create_corner fast
create_scenario -mode func -corner slow -name func_slow
create_scenario -mode func -corner fast -name func_fast

current_scenario func_slow
source $SDC_FILE
set_parasitic_parameters -early_spec maxTLU -late_spec maxTLU
set_operating_conditions -max_library saed32rvt_ss0p95v125c ss0p95v125c

current_scenario func_fast
source $SDC_FILE
set_parasitic_parameters -early_spec minTLU -late_spec minTLU
set_operating_conditions -min_library saed32rvt_ff1p16vn40c ff1p16vn40c

set_scenario_status func_slow -setup true  -hold false -leakage_power true -dynamic_power true -max_transition true -max_capacitance true
set_scenario_status func_fast -setup false -hold true
current_scenario func_slow

set_ignored_layers -max_routing_layer $MAX_LAYER

# ================================================================ 3. floorplan
initialize_floorplan -core_utilization 0.40 -shape R -side_ratio {1 1} -core_offset 10

set_block_pin_constraints -self -allowed_layers {M3 M4 M5} -sides {1 3}
place_pins -self
save_block -as ${DESIGN}_floorplan

# ================================================================ 4. power plan
create_net -power  $PWR_NET
create_net -ground $GND_NET
connect_pg_net -automatic

create_pg_ring_pattern ring_pat -horizontal_layer $RING_LAYER_H -vertical_layer $RING_LAYER_V \
    -horizontal_width 2 -vertical_width 2 -horizontal_spacing 1 -vertical_spacing 1
set_pg_strategy ring_s -core -pattern {{name: ring_pat} {nets: {VDD VSS}} {offset: {1 1}}}

create_pg_mesh_pattern mesh_pat -layers [list [list [list vertical_layer: $MESH_LAYER] \
    {width: 1} {pitch: 40} {spacing: interleaving}]]
set_pg_strategy mesh_s -core -pattern {{name: mesh_pat} {nets: {VDD VSS}}} \
    -extension {{stop: outermost_ring}}

create_pg_std_cell_conn_pattern rail_pat -layers [list $RAIL_LAYER]
set_pg_strategy rail_s -core -pattern {{name: rail_pat} {nets: {VDD VSS}}}

compile_pg -strategies {ring_s mesh_s rail_s}
check_pg_drc            > reports/pg_drc.rpt
check_pg_connectivity   > reports/pg_connectivity.rpt
save_block -as ${DESIGN}_power

# ================================================================ 5. placement
place_opt
report_qor > reports/qor_place.rpt
save_block -as ${DESIGN}_place

# ================================================================ 6. clock tree
set_scenario_status func_fast -hold true
clock_opt
report_clock_qor  > reports/clock_qor.rpt
report_qor        > reports/qor_cts.rpt
save_block -as ${DESIGN}_cts

# ================================================================ 7. routing
route_auto
route_opt
report_qor > reports/qor_route.rpt
save_block -as ${DESIGN}_route

# ================================================================ 8. finishing + checks
create_stdcell_fillers -lib_cells $FILLER_CELLS
connect_pg_net -automatic
remove_stdcell_fillers_with_violation

check_routes                         > reports/check_routes.rpt
check_lvs -max_errors 1000           > reports/check_lvs.rpt
report_timing -max_paths 20          > reports/timing_setup.rpt
report_timing -delay_type min -scenarios func_fast -max_paths 20 > reports/timing_hold.rpt
report_constraint -all_violators     > reports/violators.rpt
report_utilization                   > reports/utilization.rpt
report_power                         > reports/power.rpt

# ================================================================ 9. outputs
write_verilog -exclude {physical_only_cells} outputs/${DESIGN}_pnr.v
write_verilog -include {pg_netlist} -exclude {physical_only_cells} outputs/${DESIGN}_lvs.v
write_parasitics -output outputs/${DESIGN}
write_sdc -output outputs/${DESIGN}_pnr.sdc
write_def outputs/${DESIGN}.def
write_gds -design $DESIGN -layer_map $GDS_MAP -merge_files [list $CELL_GDS] \
          -long_names -keep_data_type outputs/${DESIGN}.gds

save_block -as ${DESIGN}_final
save_lib
puts "ICC2 done: outputs/${DESIGN}.gds"
exit
