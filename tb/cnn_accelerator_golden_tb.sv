`timescale 1ns/1ps

module cnn_accelerator_golden_tb;
    localparam int IMAGE_WIDTH   = 32;
    localparam int IMAGE_HEIGHT  = 32;
    localparam int KERNEL_SIZE   = 3;
    localparam int NUM_KERNELS   = 2;
    localparam bit RELU_ENABLE   = 1'b0;
    localparam string VECTOR_DIR = "vectors";

    localparam int NUM_TAPS      = KERNEL_SIZE * KERNEL_SIZE;
    localparam int KADDR_WIDTH   = (NUM_TAPS <= 1) ? 1 : $clog2(NUM_TAPS);
    localparam int KSEL_WIDTH    = (NUM_KERNELS <= 1) ? 1 : $clog2(NUM_KERNELS);
    localparam int OUTPUT_WIDTH  = IMAGE_WIDTH - KERNEL_SIZE + 1;
    localparam int OUTPUT_HEIGHT = IMAGE_HEIGHT - KERNEL_SIZE + 1;
    localparam int TOTAL_INPUT_PIXELS  = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam int TOTAL_OUTPUT_PIXELS = OUTPUT_WIDTH * OUTPUT_HEIGHT;

    logic clk;
    logic rst_n;
    logic start;
    logic busy;
    logic done;
    logic       pixel_valid;
    logic [7:0] pixel_in;
    logic                      kernel_we;
    logic [KSEL_WIDTH-1:0]     kernel_sel;
    logic [KADDR_WIDTH-1:0]    kernel_addr;
    logic signed [7:0]         kernel_data;
    logic relu_enable;
    logic               output_valid;
    logic signed [15:0] pixel_out [0:NUM_KERNELS-1];
    logic [$clog2(IMAGE_WIDTH)-1:0]  output_col;
    logic [$clog2(IMAGE_HEIGHT)-1:0] output_row;

    // --- Vectors loaded from golden_model.py -------------------------------
    logic [7:0]         image_mem           [0:TOTAL_INPUT_PIXELS-1];
    // kernel_mem is bank-major: bank k's taps live at [k*NUM_TAPS +: NUM_TAPS]
    logic signed [7:0]  kernel_mem          [0:NUM_KERNELS*NUM_TAPS-1];
    // expected_output_mem is position-major, bank-minor: position p bank k
    // lives at [p*NUM_KERNELS + k]
    logic [15:0]        expected_output_mem [0:TOTAL_OUTPUT_PIXELS*NUM_KERNELS-1];
    logic [0:0]         relu_cfg_mem        [0:0];

    integer errors;
    integer output_count;
    integer current_cycle;
    integer last_output_cycle;
    integer actual_fd;

    cnn_accelerator #(
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT),
        .KERNEL_SIZE  (KERNEL_SIZE),
        .NUM_KERNELS  (NUM_KERNELS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .pixel_valid(pixel_valid),
        .pixel_in(pixel_in),
        .kernel_we(kernel_we),
        .kernel_sel(kernel_sel),
        .kernel_addr(kernel_addr),
        .kernel_data(kernel_data),
        .relu_enable(relu_enable),
        .output_valid(output_valid),
        .pixel_out(pixel_out),
        .output_col(output_col),
        .output_row(output_row)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_cycle <= 0;
        else
            current_cycle <= current_cycle + 1;
    end

    task automatic reset_dut;
        begin
            rst_n = 1'b0;
            start = 1'b0;
            pixel_valid = 1'b0;
            pixel_in = 8'd0;
            kernel_we = 1'b0;
            kernel_sel = '0;
            kernel_addr = '0;
            kernel_data = 8'sd0;
            relu_enable = RELU_ENABLE;
            repeat (5) @(negedge clk);
            rst_n = 1'b1;
            repeat (2) @(negedge clk);
        end
    endtask

    task automatic program_kernel;
        begin
            for (int k = 0; k < NUM_KERNELS; k++) begin
                for (int i = 0; i < NUM_TAPS; i++) begin
                    @(negedge clk);
                    kernel_we   = 1'b1;
                    kernel_sel  = k[KSEL_WIDTH-1:0];
                    kernel_addr = i[KADDR_WIDTH-1:0];
                    kernel_data = kernel_mem[k*NUM_TAPS + i];
                end
            end
            @(negedge clk);
            kernel_we   = 1'b0;
            kernel_sel  = '0;
            kernel_addr = '0;
            kernel_data = 8'sd0;
        end
    endtask

    task automatic stream_image;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait (busy == 1'b1);

            for (int i = 0; i < TOTAL_INPUT_PIXELS; i++) begin
                @(negedge clk);
                pixel_valid = 1'b1;
                pixel_in = image_mem[i];
            end
            @(negedge clk);
            pixel_valid = 1'b0;
            pixel_in = 8'd0;
        end
    endtask

    // Checks the DUT purely against expected_output_mem, which came from golden_model.py
    always @(posedge clk) begin
        #1;
        if (output_valid) begin
            if (output_count < TOTAL_OUTPUT_PIXELS) begin
                int expected_row;
                int expected_col;
                expected_row = output_count / OUTPUT_WIDTH;
                expected_col = output_count % OUTPUT_WIDTH;

                if (output_row !== expected_row) begin
                    $display("ERROR: output[%0d] ROW mismatch: expected=%0d actual=%0d",
                        output_count, expected_row, output_row);
                    errors++;
                end
                if (output_col !== expected_col) begin
                    $display("ERROR: output[%0d] COL mismatch: expected=%0d actual=%0d",
                        output_count, expected_col, output_col);
                    errors++;
                end

                for (int k = 0; k < NUM_KERNELS; k++) begin
                    logic signed [15:0] expected_value;
                    expected_value = expected_output_mem[output_count*NUM_KERNELS + k];
                    if ($isunknown(pixel_out[k]) || $isunknown(expected_value) || (pixel_out[k] !== expected_value)) begin
                        $display("ERROR: output[%0d] bank=%0d VALUE mismatch: expected=%0d actual=%0d row=%0d col=%0d",
                            output_count, k, $signed(expected_value), $signed(pixel_out[k]), output_row, output_col);
                        errors++;
                    end
                    else begin
                        $display("PASS  [%0d] bank=%0d row=%0d col=%0d value=%0d",
                            output_count, k, output_row, output_col, $signed(pixel_out[k]));
                    end
                    $fdisplay(actual_fd, "%04h", pixel_out[k]);
                end

                if (last_output_cycle != -1 && (current_cycle - last_output_cycle != 1)) begin
                    $display("ERROR: OUTPUT BUBBLE: previous_cycle=%0d current_cycle=%0d",
                        last_output_cycle, current_cycle);
                    errors++;
                end
                last_output_cycle = current_cycle;
            end
            else begin
                $display("ERROR: Extra output detected at bank 0: %0d", $signed(pixel_out[0]));
                errors++;
            end
            output_count++;
        end
    end

    initial begin
        errors = 0;
        output_count = 0;
        current_cycle = 0;
        last_output_cycle = -1;

        $readmemh({VECTOR_DIR, "/image.hex"}, image_mem);
        $readmemh({VECTOR_DIR, "/kernel.hex"}, kernel_mem);
        $readmemh({VECTOR_DIR, "/expected_output.hex"}, expected_output_mem);
        $readmemh({VECTOR_DIR, "/config.hex"}, relu_cfg_mem);
        
        if ($isunknown(image_mem[0]) || $isunknown(image_mem[TOTAL_INPUT_PIXELS-1]) ||
            $isunknown(kernel_mem[0]) || $isunknown(kernel_mem[NUM_KERNELS*NUM_TAPS-1]) ||
            $isunknown(expected_output_mem[0]) || $isunknown(expected_output_mem[TOTAL_OUTPUT_PIXELS*NUM_KERNELS-1]) ||
            $isunknown(relu_cfg_mem[0])) begin
            $display("FATAL: one or more vector files under '%s/' failed to load (read back as X).", VECTOR_DIR);
            $display("  Check that:");
            $display("  1) you ran: python3 golden_model.py generate ... --outdir %s", VECTOR_DIR);
            $display("  2) the simulator's current working directory contains that '%s/' folder", VECTOR_DIR);
            $display("     ($readmemh paths are relative to where you launched the simulator, not this file's location)");
            $display("  3) IMAGE_WIDTH/IMAGE_HEIGHT/KERNEL_SIZE/NUM_KERNELS above match what you generated");
            $finish;
        end

        if (relu_cfg_mem[0] != RELU_ENABLE) begin
            $display("WARNING: config.hex relu_enable=%0d does not match this testbench's RELU_ENABLE=%0d -- re-run golden_model.py or fix RELU_ENABLE.",
                relu_cfg_mem[0], RELU_ENABLE);
        end

        actual_fd = $fopen({VECTOR_DIR, "/actual_output.hex"}, "w");

        reset_dut();
        program_kernel();
        stream_image();

        wait (done == 1'b1);
        repeat (3) @(negedge clk);

        $fclose(actual_fd);

        if (output_count != TOTAL_OUTPUT_PIXELS) begin
            $display("ERROR: Expected %0d outputs but received %0d", TOTAL_OUTPUT_PIXELS, output_count);
            errors++;
        end

        $display("");
        $display("==============================================");
        $display("     GOLDEN-MODEL COMPARISON (vs. Python)");
        $display("==============================================");
        $display("Image size       : %0dx%0d", IMAGE_WIDTH, IMAGE_HEIGHT);
        $display("Kernel size      : %0dx%0d", KERNEL_SIZE, KERNEL_SIZE);
        $display("Kernel banks     : %0d", NUM_KERNELS);
        $display("Expected outputs : %0d positions x %0d banks", TOTAL_OUTPUT_PIXELS, NUM_KERNELS);
        $display("Actual outputs   : %0d positions", output_count);
        $display("Errors           : %0d", errors);
        $display("Actual output log: %s/actual_output.hex (compare independently with",
            VECTOR_DIR);
        $display("                   `python3 golden_model.py compare --outdir %s --actual %s/actual_output.hex --num-kernels %0d`)",
            VECTOR_DIR, VECTOR_DIR, NUM_KERNELS);

        if (errors == 0) begin
            $display("");
            $display("**************  TEST PASSED  ****************");
        end
        else begin
            $display("");
            $display("**************  TEST FAILED  ****************");
        end
        $display("==============================================");

        $finish;
    end

endmodule
