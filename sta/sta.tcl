# OpenSTA script for mult_array (typical corner tt_025C_1v80)
# Run from the repo root:  sta sta/sta.tcl            (T = 10 ns)
#                     or:  T=<period> sta sta/sta.tcl (any other period)

set lib $::env(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
set T 10.0
if {[info exists ::env(T)]} { set T $::env(T) }

# 1. Read the cell timing library
read_liberty $lib

# 2. Read and link the netlist
read_verilog synth/mult_array_netlist.v
link_design mult_array

# 3. Clock with period T ns
create_clock -name clk -period $T [get_ports clk]

# 4. Input arrival time
set_input_delay 1.0 -clock clk [delete_from_list [all_inputs] [get_ports clk]]

# 5. Output required time
set_output_delay 1.0 -clock clk [all_outputs]

# 6. Worst setup slack
puts "Clock period T = $T ns"
report_worst_slack -max

# 7. Critical path report
report_checks -path_delay max -digits 3 > sta/mult_array_timing.rpt

exit
