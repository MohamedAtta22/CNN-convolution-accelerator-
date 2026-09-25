set REPO_ROOT [file normalize [file dirname [info script]]]
cd $REPO_ROOT
puts "Repo root (relative to this script): $REPO_ROOT"
puts "Working directory: [pwd]"

if {![file isdirectory rtl]} {
    puts "FATAL: expected an rtl/ folder under $REPO_ROOT, didn't find it."
    puts "Either this script has moved to a different folder than rtl/, or"
    puts "your repo layout doesn't match what this script assumes -- fix"
    puts "the path assumptions in the '0. Anchor' section above."
    exit 1
}
if {![file exists cnn_accelerator_synth.xdc]} {
    puts "FATAL: expected cnn_accelerator_synth.xdc alongside this script at $REPO_ROOT, didn't find it."
    exit 1
}

set part   xc7z020clg400-1
set top    cnn_accelerator
set outdir $REPO_ROOT/synth_out

# Top-level parameters -- edit these to synthesize a different
# configuration without touching the RTL
set image_width  32
set image_height 32
set kernel_size  3
set num_kernels  1
set run_implementation 1

file mkdir $outdir

read_verilog -sv {
    rtl/window_generator.sv
    rtl/line_buffer.sv
    rtl/kernel_memory.sv
    rtl/mac_array.sv
    rtl/adder_tree.sv
    rtl/post_process.sv
    rtl/output_fifo.sv
    rtl/cnn_accelerator.sv
}

read_xdc cnn_accelerator_synth.xdc

synth_design -top $top -part $part -generic IMAGE_WIDTH=$image_width \
    -generic IMAGE_HEIGHT=$image_height -generic KERNEL_SIZE=$kernel_size \
    -generic NUM_KERNELS=$num_kernels

report_timing_summary -delay_type min_max -max_paths 10 \
    -file $outdir/${top}_timing_summary.rpt

report_utilization -hierarchical \
    -file $outdir/${top}_utilization.rpt

set dsp_cells [get_cells -hierarchical -filter {REF_NAME =~ "DSP48E1"}]
if {[llength $dsp_cells] > 0} {
    report_utilization -hierarchical -cells $dsp_cells \
        -file $outdir/${top}_dsp_usage.rpt
} else {
    puts "No DSP48E1 cells found in the design -- skipping ${top}_dsp_usage.rpt."
    puts "(All multiplies were mapped to LUT fabric; see ${top}_utilization.rpt's"
    puts " DSP Blocks column, or add (* use_dsp = \"yes\" *) in mac_array.sv to force it.)"
}

write_checkpoint -force $outdir/${top}_post_synth.dcp

report_power -file $outdir/${top}_power_synth_estimate.rpt

puts "Synthesis complete. Post-synthesis reports written to $outdir/"

if {$run_implementation} {
    puts "Running implementation (place & route) for trustworthy timing/power..."

    opt_design
    place_design
    phys_opt_design
    route_design

    report_timing_summary -delay_type min_max -max_paths 10 \
        -file $outdir/${top}_post_route_timing_summary.rpt

    report_utilization -hierarchical \
        -file $outdir/${top}_post_route_utilization.rpt

    report_power -file $outdir/${top}_power.rpt

    write_checkpoint -force $outdir/${top}_post_route.dcp

    puts "Implementation complete. Post-route reports (use these for your"
    puts "report/FOM) written to $outdir/${top}_post_route_*.rpt and"
    puts "$outdir/${top}_power.rpt"
} else {
    puts "run_implementation=0 -- skipped place & route. ${top}_power_synth_estimate.rpt"
    puts "is a rough pre-placement estimate only; set run_implementation to 1"
    puts "and re-run for a real post-route power number before reporting it."
}
