# tech_setup.tcl - library/PDK paths for the Synopsys flow (DC, ICC2, PrimeTime, Formality)
#
# Defaults follow the Synopsys SAED32nm educational kit (SAED32_EDK) that is
# usually installed alongside university Synopsys licenses. Edit the paths for
# your installation, or point them at another kit (SCL 180 nm, SAED14, ...).

set SAED       $::env(HOME)/pdk/SAED32_EDK

# timing (.db) - slow corner for setup, fast corner for hold
set DB_SLOW    $SAED/lib/stdcell_rvt/db_nldm/saed32rvt_ss0p95v125c.db
set DB_FAST    $SAED/lib/stdcell_rvt/db_nldm/saed32rvt_ff1p16vn40c.db

# ICC2 physical data
set TECH_TF    $SAED/tech/milkyway/saed32nm_1p9m_mw.tf
set REF_NDM    $SAED/lib/stdcell_rvt/ndm/saed32rvt_c.ndm
set TLUP_MAX   $SAED/tech/star_rcxt/saed32nm_1p9m_Cmax.tluplus
set TLUP_MIN   $SAED/tech/star_rcxt/saed32nm_1p9m_Cmin.tluplus
set TLUP_MAP   $SAED/tech/star_rcxt/saed32nm_tf_itf_tluplus.map
set GDS_MAP    $SAED/tech/milkyway/saed32nm_1p9m_gdsout_mw.map
set CELL_GDS   $SAED/lib/stdcell_rvt/gds/saed32nm_rvt.gds
set NXTGRD_MAX $SAED/tech/star_rcxt/saed32nm_1p9m_Cmax.nxtgrd

# library-specific names
set PWR_NET      VDD
set GND_NET      VSS
set RING_LAYER_H M7
set RING_LAYER_V M8
set MESH_LAYER   M8
set RAIL_LAYER   M1
set FILLER_CELLS {*/SHFILL128_RVT */SHFILL64_RVT */SHFILL3_RVT */SHFILL2_RVT */SHFILL1_RVT}
set MAX_LAYER    M8

# design
set DESIGN    rv32_core
set RTL_DIR   [file normalize [file dirname [info script]]/../../rtl]
set RTL_FILES [list $RTL_DIR/rv32_alu.v $RTL_DIR/rv32_regfile.v \
                    $RTL_DIR/rv32_decoder.v $RTL_DIR/rv32_core.v]
set SDC_FILE  [file normalize [file dirname [info script]]/../constraints/rv32_core.sdc]
