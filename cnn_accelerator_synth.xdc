# --- Primary clock -----------------------------------------------------
create_clock -name clk -period 10.000 [get_ports clk]

# --- Reset ---------------------------------------------------------------
set_false_path -from [get_ports rst_n]

# --- Placeholder I/O timing ----------------------------------------------
set_input_delay  -clock clk 2.000 [get_ports {pixel_in* pixel_valid kernel_we kernel_sel* kernel_addr* kernel_data* relu_enable start}]
set_output_delay -clock clk 2.000 [get_ports {pixel_out* output_valid output_col* output_row* busy done}]
