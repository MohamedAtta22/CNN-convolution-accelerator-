set REPO_ROOT [file normalize [file dirname [info script]]]
cd $REPO_ROOT
echo "Repo root (relative to this script): $REPO_ROOT"
echo "Working directory: [pwd]"

if {![file isdirectory rtl] || ![file isdirectory tb]} {
    echo "FATAL: expected rtl/ and tb/ folders under $REPO_ROOT, didn't find both."
    echo "Either this script has moved to a different folder than rtl/tb, or"
    echo "your repo layout doesn't match what this script assumes -- fix the"
    echo "path assumptions in the '0. Anchor' section above."
    return
}

# --- 1. Fresh work library ------------------------------------------------
if {[file isdirectory work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# --- 2. Compile ------------------------------------------------------------
vlog -sv +acc \
    rtl/window_generator.sv \
    rtl/line_buffer.sv \
    rtl/kernel_memory.sv \
    rtl/mac_array.sv \
    rtl/adder_tree.sv \
    rtl/post_process.sv \
    rtl/output_fifo.sv \
    rtl/cnn_accelerator.sv \
    tb/cnn_accelerator_tb.sv

# --- 3. Elaborate + load ----------------------------------------------------
vsim -voptargs=+acc work.cnn_accelerator_tb

# --- 4. Waves ----------------------------------------------------------------
add wave -r sim:/cnn_accelerator_tb/*
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
wave zoom full

# --- 5. Run --------------------------------------------------------------
run -all

echo "Done. Check the transcript above for TEST PASSED / TEST FAILED."
