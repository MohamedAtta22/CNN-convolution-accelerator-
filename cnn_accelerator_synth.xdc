create_clock -name clk -period 10.000 [get_ports clk]

# --- Reset ---------------------------------------------------------------
set_false_path -from [get_ports rst_n]

set_false_path -from [get_ports {pixel_in* pixel_valid kernel_we kernel_sel* kernel_addr* kernel_data* relu_enable start}]
set_false_path -to   [get_ports {pixel_out* output_valid output_col* output_row* busy done}]
