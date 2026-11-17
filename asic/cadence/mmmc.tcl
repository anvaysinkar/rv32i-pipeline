# mmmc.tcl - multi-mode multi-corner setup for Innovus / Tempus (legacy UI)
create_library_set -name ls_slow -timing [list $LIB_SLOW]
create_library_set -name ls_fast -timing [list $LIB_FAST]

if {[file exists $QRC_TECH]} {
    create_rc_corner -name rc_typ -qx_tech_file $QRC_TECH -T 25
} else {
    create_rc_corner -name rc_typ -cap_table $CAP_TABLE -T 25
}

create_delay_corner -name dc_slow -library_set ls_slow -rc_corner rc_typ
create_delay_corner -name dc_fast -library_set ls_fast -rc_corner rc_typ

create_constraint_mode -name func -sdc_files [list $SDC_FILE]

create_analysis_view -name view_setup -constraint_mode func -delay_corner dc_slow
create_analysis_view -name view_hold  -constraint_mode func -delay_corner dc_fast

set_analysis_view -setup {view_setup} -hold {view_hold}
