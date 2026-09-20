`timescale 1ns/1ps

module cnn_accelerator_tb;
    localparam int IMAGE_WIDTH  = 32;
    localparam int IMAGE_HEIGHT = 32;
    localparam int KERNEL_SIZE  = 3;
    localparam int NUM_KERNELS  = 2;
    localparam int NUM_TAPS     = KERNEL_SIZE * KERNEL_SIZE;
    localparam int KADDR_WIDTH  = (NUM_TAPS <= 1) ? 1 : $clog2(NUM_TAPS);
    localparam int KSEL_WIDTH   = (NUM_KERNELS <= 1) ? 1 : $clog2(NUM_KERNELS);
    localparam int OUTPUT_WIDTH = IMAGE_WIDTH - KERNEL_SIZE + 1;
    localparam int OUTPUT_HEIGHT = IMAGE_HEIGHT - KERNEL_SIZE + 1;
    localparam int TOTAL_INPUT_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
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
    logic [7:0] image [0:TOTAL_INPUT_PIXELS-1];
    logic signed [7:0] test_kernel [0:NUM_KERNELS-1][0:NUM_TAPS-1];
    logic signed [15:0] expected_output [0:NUM_KERNELS-1][0:TOTAL_OUTPUT_PIXELS-1];
    integer errors;
    integer output_count;
    integer expected_row;
    integer expected_col;
    integer current_cycle;
    integer last_output_cycle;
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
    initial begin
        errors = 0;
        output_count = 0;
        expected_row = 0;
        expected_col = 0;
        current_cycle = 0;
        last_output_cycle = -1;
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
            relu_enable = 1'b0;
            repeat (5) @(negedge clk);
            rst_n = 1'b1;
            repeat (2) @(negedge clk);
            $display("");
            $display("========================================");
            $display("RESET COMPLETE");
            $display("========================================");
        end
    endtask

    task automatic write_kernel(
        input integer sel,
        input integer address,
        input integer value
    );
        begin
            @(negedge clk);
            kernel_we   = 1'b1;
            kernel_sel  = sel[KSEL_WIDTH-1:0];
            kernel_addr = address[KADDR_WIDTH-1:0];
            kernel_data = value;

            @(negedge clk);
            kernel_we   = 1'b0;
            kernel_sel  = '0;
            kernel_addr = '0;
            kernel_data = 8'sd0;

        end

    endtask

    task automatic program_kernel;
        begin
            $display("");
            $display("Programming %0d kernel bank(s)...", NUM_KERNELS);
            for (int k = 0; k < NUM_KERNELS; k++) begin
                for (int i = 0; i < NUM_TAPS; i++) begin
                    write_kernel(
                        k,
                        i,
                        test_kernel[k][i]
                    );
                end
            end
            $display("Kernel(s) programmed.");
        end

    endtask

    task automatic generate_image;
        begin
            for (int row = 0; row < IMAGE_HEIGHT; row++) begin
                for (int col = 0; col < IMAGE_WIDTH; col++) begin
                    image[row * IMAGE_WIDTH + col] = (row * IMAGE_WIDTH + col) & 8'hFF;
                end

            end

        end

    endtask

    task automatic calculate_expected;
        integer accumulator;
        integer pixel_value;
        integer coefficient;
        begin
            for (int k = 0; k < NUM_KERNELS; k++) begin
                for (int row = 0; row < OUTPUT_HEIGHT; row++) begin
                    for (int col = 0; col < OUTPUT_WIDTH; col++) begin
                        accumulator = 0;
                        for (int kr = 0; kr < KERNEL_SIZE; kr++) begin
                            for (int kc = 0; kc < KERNEL_SIZE; kc++) begin
                                pixel_value = image[(row + kr) * IMAGE_WIDTH + (col + kc)];
                                coefficient = test_kernel[k][kr * KERNEL_SIZE + kc];
                                accumulator = accumulator + pixel_value * coefficient;
                            end

                        end

                        if (accumulator > 32767) begin
                            expected_output[k][row * OUTPUT_WIDTH + col] = 16'sh7FFF;
                        end

                        else if (accumulator < -32768) begin
                            expected_output[k][row * OUTPUT_WIDTH + col] = 16'sh8000;
                        end

                        else begin
                            expected_output[k][row * OUTPUT_WIDTH + col] = accumulator;
                        end

                    end

                end
            end

        end

    endtask

    task automatic stream_image;
        begin
            $display("");
            $display("Starting image stream...");
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait (busy == 1'b1);
            $display("Accelerator is running.");

            for (int i = 0; i < TOTAL_INPUT_PIXELS; i++) begin
                @(negedge clk);
                pixel_valid = 1'b1;
                pixel_in = image[i];

            end
            @(negedge clk);
            pixel_valid = 1'b0;
            pixel_in = 8'd0;
            $display(
                "Image stream complete: %0d pixels",
                TOTAL_INPUT_PIXELS
            );

        end

    endtask
    always @(posedge clk) begin
        #1;
        if (output_valid) begin
            if (output_count >= TOTAL_OUTPUT_PIXELS) begin
                $display(
                    "ERROR: Extra output detected at bank 0: %0d",
                    $signed(pixel_out[0])
                );

                errors++;

            end

            else begin

                expected_row = output_count / OUTPUT_WIDTH;

                expected_col = output_count % OUTPUT_WIDTH;

                if (output_row !== expected_row) begin
                    $display(
                        "ERROR: output[%0d] ROW mismatch: expected=%0d actual=%0d",
                        output_count,
                        expected_row,
                        output_row
                    );
                    errors++;
                end

                if (output_col !== expected_col) begin
                    $display(
                        "ERROR: output[%0d] COL mismatch: expected=%0d actual=%0d",
                        output_count,
                        expected_col,
                        output_col
                    );
                    errors++;
                end

                for (int k = 0; k < NUM_KERNELS; k++) begin
                    if ($isunknown(pixel_out[k]) || (pixel_out[k] !== expected_output[k][output_count])) begin
                        $display(
                            "ERROR: output[%0d] bank=%0d VALUE mismatch: expected=%0d actual=%0d row=%0d col=%0d",
                            output_count,
                            k,
                            $signed(expected_output[k][output_count]),
                            $signed(pixel_out[k]),
                            output_row,
                            output_col
                        );
                        errors++;
                    end
                    else begin
                        $display(
                            "PASS  [%0d] bank=%0d row=%0d col=%0d value=%0d",
                            output_count,
                            k,
                            output_row,
                            output_col,
                            $signed(pixel_out[k])
                        );
                    end
                end
                if (last_output_cycle != -1) begin
                    if (current_cycle - last_output_cycle != 1) begin
                        $display(
                            "ERROR: OUTPUT BUBBLE: previous_cycle=%0d current_cycle=%0d",
                            last_output_cycle,
                            current_cycle
                        );
                        errors++;
                    end
                end
                last_output_cycle = current_cycle;
                output_count++;
            end
        end
    end
    initial begin
        // Bank 0: horizontal edge-detect
        // Bank 1: a distinct all-positive averaging-style kernel,
        // so a channel-swap or cross-talk bug between banks would
        // show up as a VALUE mismatch instead of silently passing.
        test_kernel[0][0] =  8'sd1;  test_kernel[0][1] =  8'sd0;  test_kernel[0][2] = -8'sd1;
        test_kernel[0][3] =  8'sd1;  test_kernel[0][4] =  8'sd0;  test_kernel[0][5] = -8'sd1;
        test_kernel[0][6] =  8'sd1;  test_kernel[0][7] =  8'sd0;  test_kernel[0][8] = -8'sd1;

        test_kernel[1][0] =  8'sd1;  test_kernel[1][1] =  8'sd2;  test_kernel[1][2] =  8'sd1;
        test_kernel[1][3] =  8'sd2;  test_kernel[1][4] =  8'sd4;  test_kernel[1][5] =  8'sd2;
        test_kernel[1][6] =  8'sd1;  test_kernel[1][7] =  8'sd2;  test_kernel[1][8] =  8'sd1;

        reset_dut();

        generate_image();

        calculate_expected();

        program_kernel();

        relu_enable = 1'b0;

        stream_image();

        wait (done == 1'b1);

        repeat (3) @(negedge clk);

        if (output_count != TOTAL_OUTPUT_PIXELS) begin
            $display(
                "ERROR: Expected %0d outputs but received %0d",
                TOTAL_OUTPUT_PIXELS,
                output_count
            );
            errors++;
        end

        $display("");
        $display("==============================================");
        $display("              TEST SUMMARY");
        $display("==============================================");
        $display(
            "Image size       : %0dx%0d",
            IMAGE_WIDTH,
            IMAGE_HEIGHT
        );

        $display(
            "Kernel size      : %0dx%0d",
            KERNEL_SIZE,
            KERNEL_SIZE
        );

        $display(
            "Kernel banks     : %0d",
            NUM_KERNELS
        );

        $display(
            "Expected outputs : %0d (x%0d banks)",
            TOTAL_OUTPUT_PIXELS,
            NUM_KERNELS
        );

        $display(
            "Actual outputs   : %0d",
            output_count
        );

        $display(
            "Errors           : %0d",
            errors
        );

        if (errors == 0) begin
            $display("");
            $display("**************************************");
            $display("            TEST PASSED");
            $display("**************************************");
        end

        else begin
            $display("");
            $display("**************************************");
            $display("            TEST FAILED");
            $display("**************************************");
        end

        $display("==============================================");

        $finish;

    end

endmodule
