# innovus_pnr.tcl - floorplan, power, place, CTS, route, signoff checks, GDSII
#   cd asic/cadence && innovus -files innovus_pnr.tcl -log logs/innovus
# Run genus_syn.tcl first. Steps are separated so you can paste them one at a
# time into the Innovus console and look at the layout after each.
source tech_setup.tcl
file mkdir outputs reports logs db

# ================================================================ 1. import
set init_verilog   outputs/${DESIGN}_syn.v
set init_top_cell  $DESIGN
set init_lef_file  $LEF_FILES
set init_mmmc_file mmmc.tcl
set init_pwr_net   $PWR_NET
set init_gnd_net   $GND_NET
init_design

setDesignMode -process $PROCESS_NODE
setMaxRouteLayer [string range $TOP_ROUTE_LYR 5 end]

# ================================================================ 2. floorplan
# aspect ratio 1.0, 40 % core utilisation, 10 um core-to-boundary margin
floorPlan -site $CORE_SITE -r 1.0 0.40 10 10 10 10

globalNetConnect $PWR_NET -type pgpin -pin $PWR_NET -all -override
globalNetConnect $GND_NET -type pgpin -pin $GND_NET -all -override
globalNetConnect $PWR_NET -type tiehi -all -override
globalNetConnect $GND_NET -type tielo -all -override

# I/O pins: instruction bus on the left, data bus on the right
setPinAssignMode -pinEditInBatch true
editPin -side Left  -layer 3 -spreadType center -spacing 2 \
        -pin [concat clk rst_n [get_object_name [get_ports imem_*]]]
editPin -side Right -layer 3 -spreadType center -spacing 1 \
        -pin [get_object_name [get_ports {dmem_* retire}]]
setPinAssignMode -pinEditInBatch false

saveDesign db/01_floorplan.enc

# ================================================================ 3. power plan
addRing -nets [list $PWR_NET $GND_NET] -type core_rings -follow core \
        -layer [list top $RING_LAYER_H bottom $RING_LAYER_H left $RING_LAYER_V right $RING_LAYER_V] \
        -width 2 -spacing 1 -offset 1
addStripe -nets [list $PWR_NET $GND_NET] -layer $STRIPE_LAYER -direction vertical \
          -width 1 -spacing 1 -set_to_set_distance 40 -start_from left -start_offset 20
sroute -connect {corePin blockPin padPin floatingStripe} -nets [list $PWR_NET $GND_NET]
verifyConnectivity -type special -report reports/pg_connectivity.rpt

saveDesign db/02_power.enc

# ================================================================ 4. placement
setPlaceMode -timingDriven true -congEffort auto -place_global_place_io_pins false
placeDesign
optDesign -preCTS -outDir reports/preCTS
saveDesign db/03_place.enc

# ================================================================ 5. clock tree
set_ccopt_property buffer_cells   [list]   ;# empty = let CCOpt pick from the library
create_ccopt_clock_tree_spec -file outputs/ccopt.spec
source outputs/ccopt.spec
ccopt_design
report_ccopt_clock_trees -file reports/clock_trees.rpt
report_ccopt_skew_groups -file reports/skew_groups.rpt

optDesign -postCTS        -outDir reports/postCTS
optDesign -postCTS -hold  -outDir reports/postCTS_hold
saveDesign db/04_cts.enc

# ================================================================ 6. routing
setNanoRouteMode -routeWithTimingDriven true -routeWithSiDriven true \
                 -drouteFixAntenna true -routeInsertAntennaDiode true
routeDesign

setAnalysisMode -analysisType onChipVariation -cppr both
setExtractRCMode -engine postRoute -effortLevel medium
optDesign -postRoute       -outDir reports/postRoute
optDesign -postRoute -hold -outDir reports/postRoute_hold
saveDesign db/05_route.enc

# ================================================================ 7. finishing
addFiller -cell $FILLER_CELLS -prefix FILLER
ecoRoute

# ================================================================ 8. checks
verify_drc            -report reports/drc.rpt -limit 10000
verifyConnectivity    -report reports/connectivity.rpt
verifyProcessAntenna  -report reports/antenna.rpt
checkPlace                    reports/check_place.rpt

timeDesign -postRoute        -outDir reports/signoff_setup
timeDesign -postRoute -hold  -outDir reports/signoff_hold
report_area  > reports/area_pnr.rpt
report_power -outfile reports/power_pnr.rpt

# ================================================================ 9. outputs
extractRC
rcOut -spef outputs/${DESIGN}.spef -rc_corner rc_typ
write_sdf  outputs/${DESIGN}_pnr.sdf
saveNetlist outputs/${DESIGN}_pnr.v
# power-aware netlist for LVS (physical-only cells excluded)
saveNetlist outputs/${DESIGN}_lvs.v -includePowerGround -excludeLeafCell \
            -excludeCellInst $FILLER_CELLS
defOut -floorplan -netlist -routing outputs/${DESIGN}.def
write_lef_abstract outputs/${DESIGN}.lef

streamOut outputs/${DESIGN}.gds -mapFile $GDS_MAP -merge [list $CELL_GDS] \
          -stripes 1 -units 2000 -mode ALL

saveDesign db/06_final.enc
puts "Innovus done: outputs/${DESIGN}.gds"
