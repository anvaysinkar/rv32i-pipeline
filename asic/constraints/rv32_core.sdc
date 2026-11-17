# rv32_core.sdc - timing constraints for hardening rv32_core as an ASIC block
# Used by LibreLane/OpenROAD, Cadence Genus/Innovus/Tempus and Synopsys DC/ICC2/PT.
#
# Plain SDC with literal numbers so every tool parses it the same way.
# To retime: change the period (20.0 ns = 50 MHz) and the delays (30 % of it),
# and keep CLOCK_PERIOD in asic/openlane/config.json in step.
#
# The memory ports go to SRAM macros (or a higher-level SoC): output delay models
# the SRAM setup requirement, input delay models the SRAM clock-to-Q.

create_clock -name clk -period 20.0 [get_ports clk]
set_clock_uncertainty 0.25 [get_clocks clk]
set_clock_transition  0.15 [get_clocks clk]

# data inputs listed explicitly (portable across OpenSTA, Genus and DC)
set_input_delay  6.0 -clock clk [get_ports {imem_rdata* dmem_rdata*}]
set_output_delay 6.0 -clock clk [all_outputs]

# reset is synchronised outside the block (see fpga/nexys4/nexys4_top.v),
# so it behaves as a normal input with synchronous release
set_input_delay 10.0 -clock clk [get_ports rst_n]

set_max_fanout     16  [current_design]
set_max_transition 1.0 [current_design]
set_load 0.02 [all_outputs]
