set REPO_ROOT [file normalize [file dirname [info script]]]
cd $REPO_ROOT
echo "Repo root (relative to this script): $REPO_ROOT"
echo "Working directory: [pwd]"

if {![file isdirectory rtl] || ![file isdirectory tb] || ![file isdirectory python]} {
    echo "FATAL: expected rtl/, tb/, and python/ folders under $REPO_ROOT, didn't find all three."
    echo "Either this script has moved to a different folder than rtl/tb/python,"
    echo "or your repo layout doesn't match what this script assumes -- fix the"
    echo "path assumptions in the '0. Anchor' section above."
    return
}

# --- 1. Generate golden vectors ---------------------------------------------
set GOLDEN_ARGS "generate --width 32 --height 32 --kernel-size 3 --num-kernels 2 --relu 0 --seed 1234 --outdir vectors"

set venv_python_win  "$REPO_ROOT/.venv/Scripts/python.exe"
set venv_python_unix "$REPO_ROOT/.venv/bin/python"
set python_candidates {}
if {[file exists $venv_python_win]}  { lappend python_candidates $venv_python_win }
if {[file exists $venv_python_unix]} { lappend python_candidates $venv_python_unix }
foreach c {python python3 py} { lappend python_candidates $c }

if {[llength $python_candidates] > 0 && ([lindex $python_candidates 0] eq $venv_python_win || [lindex $python_candidates 0] eq $venv_python_unix)} {
    echo "Found project venv, will prefer it: [lindex $python_candidates 0]"
} else {
    echo "No .venv/ found at $REPO_ROOT -- falling back to system python."
    echo "(Run 'uv venv' then 'uv pip install -r requirements.txt' at the repo root to avoid this.)"
}

set generated 0
set working_python ""
foreach PYTHON_CMD $python_candidates {
    if {$generated} { break }
    echo "Trying: $PYTHON_CMD python/golden_model.py $GOLDEN_ARGS"
    if {[catch {eval exec [list $PYTHON_CMD] python/golden_model.py $GOLDEN_ARGS} result]} {
        echo "  -> failed: $result"
    } else {
        echo $result
        set generated 1
        set working_python $PYTHON_CMD
    }
}

if {!$generated} {
    echo "FATAL: could not run golden_model.py with any of: $python_candidates"
    echo "Most likely numpy isn't installed wherever these point. Set up the"
    echo "isolated venv (recommended, keeps your system Python untouched):"
    echo "    cd $REPO_ROOT"
    echo "    uv venv"
    echo "    uv pip install -r requirements.txt"
    echo "then re-run this script -- it will pick up .venv/ automatically."
    return
}

# --- 2. Verify the vectors actually landed where $readmemh will look -------
set required_files {vectors/image.hex vectors/kernel.hex vectors/expected_output.hex vectors/config.hex}
set missing {}
foreach f $required_files {
    if {![file exists $f]} {
        lappend missing $f
    }
}
if {[llength $missing] > 0} {
    echo "FATAL: vector generation reported success, but these files are still missing from $REPO_ROOT:"
    foreach f $missing { echo "    $f" }
    echo "Contents of vectors/ (if it exists):"
    foreach f [glob -nocomplain vectors/*] { echo "    $f" }
    echo "This usually means golden_model.py wrote its output relative to a"
    echo "different current directory than Questa's. Try running the generate"
    echo "command by hand in a terminal, cd'd to $REPO_ROOT first, then"
    echo "re-run this script."
    return
}
echo "Vectors confirmed present in $REPO_ROOT/vectors/"

# --- 3. Fresh work library ------------------------------------------------
if {[file isdirectory work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# --- 4. Compile ------------------------------------------------------------
vlog -sv +acc \
    rtl/window_generator.sv \
    rtl/line_buffer.sv \
    rtl/kernel_memory.sv \
    rtl/mac_array.sv \
    rtl/adder_tree.sv \
    rtl/post_process.sv \
    rtl/output_fifo.sv \
    rtl/cnn_accelerator.sv \
    tb/cnn_accelerator_golden_tb.sv

# --- 5. Elaborate + load ----------------------------------------------------
vsim -voptargs=+acc work.cnn_accelerator_golden_tb

# --- 6. Waves ----------------------------------------------------------------
add wave -r sim:/cnn_accelerator_golden_tb/*
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
wave zoom full

# --- 7. Run --------------------------------------------------------------
run -all

echo "Done. Check the transcript above for TEST PASSED / TEST FAILED."
echo "Independent cross-check: [list $working_python] python/golden_model.py compare --outdir $REPO_ROOT/vectors --actual $REPO_ROOT/vectors/actual_output.hex --num-kernels 2"
