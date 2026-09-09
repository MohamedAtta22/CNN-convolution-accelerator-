# CNN Convolution Accelerator

An RTL implementation of a streaming 3x3 CNN convolution accelerator for a
single 8-bit grayscale image channel. The design accepts one pixel per clock
in raster-scan order, applies a programmable signed 3x3 kernel, optionally
applies ReLU, and emits signed 16-bit valid-convolution results in raster
order.

## Current Configuration

| Property | Value |
| --- | --- |
| Input image | 32x32 unsigned 8-bit pixels |
| Kernel | Programmable 3x3 signed 8-bit coefficients |
| Convolution | Valid, stride 1 |
| Output image | 30x30 signed 16-bit pixels |
| Activation | Optional ReLU |
| Input rate | One pixel per clock |
| Output rate | One result per clock after FIFO prefill |

## Architecture

```text
pixel stream
    |
    v
line_buffer + window_generator
    |
    v
3x3 pixel window --> mac_array --> adder_tree --> post_process
                                                   |
                                                   v
                                              output_fifo
                                                   |
                                                   v
                                  pixel_out, output_row, output_col
```

- `line_buffer.sv` stores the two preceding image rows and provides the
  vertical data required for each window.
- `window_generator.sv` combines the line-buffer values with horizontal shift
  registers to form each valid 3x3 window and its output coordinate.
- `kernel_memory.sv` stores nine programmable signed coefficients.
- `mac_array.sv` performs the nine pixel-coefficient multiplications.
- `adder_tree.sv` reduces the products through a three-stage registered adder
  tree.
- `post_process.sv` applies optional ReLU and saturates the result to signed
  16-bit range.
- `output_fifo.sv` absorbs the two invalid input columns at each output-row
  boundary, enabling a continuous output stream after prefill.
- `cnn_accelerator.sv` integrates the datapath, coordinate alignment, FIFO,
  and IDLE/RUN/DRAIN/DONE control states.

The first valid result is produced for the window whose bottom-right input
pixel is `(2,2)` and is labeled output coordinate `(0,0)`. For a 32x32 input,
the final result is `(29,29)`.

## Interface

The top-level module is `cnn_accelerator` in `rtl/cnn_accelerator.sv`.

- Assert `start` to begin a transaction.
- Program kernel values through `kernel_we`, `kernel_addr`, and `kernel_data`
  while the accelerator is idle.
- Present input pixels through `pixel_valid` and `pixel_in` in raster order.
- Sample `pixel_out`, `output_row`, and `output_col` whenever `output_valid`
  is asserted.
- `busy` is high while processing; `done` pulses after the final output.

## Verification

`tb/cnn_accelerator_tb.sv` generates a 32x32 ramp image, programs the kernel

```text
 1  0 -1
 1  0 -1
 1  0 -1
```

and checks all 900 output values, raster-order coordinates, output count, and
continuous output throughput.

Example QuestaSim run from the repository root:

```powershell
vlib work
vlog -sv -work work rtl\line_buffer.sv rtl\window_generator.sv rtl\kernel_memory.sv rtl\mac_array.sv rtl\adder_tree.sv rtl\post_process.sv rtl\output_fifo.sv rtl\cnn_accelerator.sv tb\cnn_accelerator_tb.sv
vsim -c -lib work cnn_accelerator_tb -do "run -all; quit -f"
```

The checked configuration completes with 900 outputs and zero testbench
errors.
