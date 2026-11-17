# tech_setup.tcl - library/PDK paths for the Cadence flow (Genus, Innovus, Tempus)
#
# Edit this one file for your PDK. The defaults below follow the layout of
# Cadence's generic 45 nm kit (GPDK045 + GSCLIB045) that ships with most
# university/C2S installations. For SCL 180 nm or another foundry kit, point the
# same variables at that kit's .lib/.lef/QRC/GDS files and fix the names of
# the core site, filler cells and metal layers.

set PDK_ROOT   $::env(HOME)/pdk/gsclib045_all_v4.4/gsclib045

# timing libraries (.lib) - worst corner for setup, best corner for hold
set LIB_SLOW   $PDK_ROOT/timing/slow_vdd1v0_basicCells.lib
set LIB_FAST   $PDK_ROOT/timing/fast_vdd1v0_basicCells.lib

# physical libraries: technology LEF first, then the cell LEF
set LEF_FILES  [list $PDK_ROOT/lef/gsclib045_tech.lef \
                     $PDK_ROOT/lef/gsclib045_macro.lef]

# parasitic extraction: QRC tech file (preferred) or cap tables
set QRC_TECH   $PDK_ROOT/qrc/qx/gpdk045.tch
set CAP_TABLE  ""

# GDS stream-out
set GDS_MAP    $PDK_ROOT/../../gpdk045_v_6_0/streamOut.map
set CELL_GDS   $PDK_ROOT/gds/gsclib045.gds

# library-specific names used by Innovus
set CORE_SITE      CoreSite
set PWR_NET        VDD
set GND_NET        VSS
set RING_LAYER_H   Metal9
set RING_LAYER_V   Metal8
set STRIPE_LAYER   Metal8
set FILLER_CELLS   {FILL64 FILL32 FILL16 FILL8 FILL4 FILL2 FILL1}
set TOP_ROUTE_LYR  Metal9
set PROCESS_NODE   45

# design
set DESIGN   rv32_core
set RTL_DIR  [file normalize [file dirname [info script]]/../../rtl]
set RTL_FILES [list $RTL_DIR/rv32_alu.v $RTL_DIR/rv32_regfile.v \
                    $RTL_DIR/rv32_decoder.v $RTL_DIR/rv32_core.v]
set SDC_FILE [file normalize [file dirname [info script]]/../constraints/rv32_core.sdc]
