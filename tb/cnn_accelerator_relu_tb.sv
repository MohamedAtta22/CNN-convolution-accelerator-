`timescale 1ns/1ps

module cnn_accelerator_relu_tb;
    localparam int IMAGE_WIDTH  = 9;
    localparam int IMAGE_HEIGHT = 3;
    localparam int KERNEL_SIZE  = 3;
    localparam int NUM_KERNELS  = 2;
    localparam int NUM_TAPS     = KERNEL_SIZE * KERNEL_SIZE;
    localparam int KADDR_WIDTH  = (NUM_TAPS <= 1) ? 1 : $clog2(NUM_TAPS);
    localparam int KSEL_WIDTH   = (NUM_KERNELS <= 1) ? 1 : $clog2(NUM_KERNELS);
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

    logic [7:0]         image [0:TOTAL_INPUT_PIXELS-1];
    logic signed [7:0]  test_kernel [0:NUM_KERNELS-1][0:NUM_TAPS-1];
    logic signed [15:0] expected_norelu [0:NUM_KERNELS-1][0:TOTAL_OUTPUT_PIXELS-1];
    logic signed [15:0] expected_relu   [0:NUM_KERNELS-1][0:TOTAL_OUTPUT_PIXELS-1];

    integer errors;
    integer output_count;
    integer current_cycle;
    integer last_output_cycle;
    bit     active_relu;

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
        if (!rst_n) current_cycle <= 0;
        else current_cycle <= current_cycle + 1;
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
        end
    endtask

    task automatic write_kernel(input integer sel, input integer address, input integer value);
        begin
            @(negedge clk);
            kernel_we   = 1'b1;
            kernel_sel  = sel[KSEL_WIDTH-1:0];
            kernel_addr = address[KADDR_WIDTH-1:0];
            kernel_data = value;
            @(negedge clk);
            kernel_we   = 1'b0;
        end
    endtask

    task automatic program_kernels;
        begin
            for (int k = 0; k < NUM_KERNELS; k++)
                for (int i = 0; i < NUM_TAPS; i++)
                    write_kernel(k, i, test_kernel[k][i]);
            @(negedge clk);
            kernel_sel  = '0;
            kernel_addr = '0;
            kernel_data = 8'sd0;
        end
    endtask

    task automatic build_image;
        begin
            for (int i = 0; i < TOTAL_INPUT_PIXELS; i++)
                image[i] = 8'd0;
            // col=0: p0=3,p1=0,p2=119 -> bank0 = 127*3+127*0+1*119 = 500
            image[0] = 3; image[1] = 0; image[2] = 119;
            // col=3: p0=255,p1=3,p2=3 -> bank0 = 32769
            image[3] = 255; image[4] = 3; image[5] = 3;
        end
    endtask

    task automatic calculate_expected_norelu;
        integer acc;
        integer pixel_value;
        integer coefficient;
        begin
            for (int k = 0; k < NUM_KERNELS; k++) begin
                for (int col = 0; col < OUTPUT_WIDTH; col++) begin
                    acc = 0;
                    for (int kr = 0; kr < KERNEL_SIZE; kr++) begin
                        for (int kc = 0; kc < KERNEL_SIZE; kc++) begin
                            pixel_value = image[(0 + kr) * IMAGE_WIDTH + (col + kc)];
                            coefficient = test_kernel[k][kr * KERNEL_SIZE + kc];
                            acc = acc + pixel_value * coefficient;
                        end
                    end
                    if (acc > 32767)       expected_norelu[k][col] = 16'sh7FFF;
                    else if (acc < -32768) expected_norelu[k][col] = 16'sh8000;
                    else                   expected_norelu[k][col] = acc;
                end
            end
        end
    endtask

    task automatic calculate_expected_relu;
        integer acc;
        integer pixel_value;
        integer coefficient;
        begin
            for (int k = 0; k < NUM_KERNELS; k++) begin
                for (int col = 0; col < OUTPUT_WIDTH; col++) begin
                    acc = 0;
                    for (int kr = 0; kr < KERNEL_SIZE; kr++) begin
                        for (int kc = 0; kc < KERNEL_SIZE; kc++) begin
                            pixel_value = image[(0 + kr) * IMAGE_WIDTH + (col + kc)];
                            coefficient = test_kernel[k][kr * KERNEL_SIZE + kc];
                            acc = acc + pixel_value * coefficient;
                        end
                    end
                    if (acc < 0)            expected_relu[k][col] = 16'sd0;
                    else if (acc > 32767)   expected_relu[k][col] = 16'sh7FFF;
                    else if (acc < -32768)  expected_relu[k][col] = 16'sh8000;
                    else                    expected_relu[k][col] = acc;
                end
            end
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
                pixel_in = image[i];
            end
            @(negedge clk);
            pixel_valid = 1'b0;
            pixel_in = 8'd0;
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (output_valid) begin
            if (output_count < TOTAL_OUTPUT_PIXELS) begin
                int expected_col;
                expected_col = output_count;

                if (output_col !== expected_col) begin
                    $display("ERROR: [relu=%0d] output[%0d] COL mismatch: expected=%0d actual=%0d",
                        active_relu, output_count, expected_col, output_col);
                    errors++;
                end

                for (int k = 0; k < NUM_KERNELS; k++) begin
                    logic signed [15:0] expected_value;
                    expected_value = active_relu ? expected_relu[k][output_count] : expected_norelu[k][output_count];
                    if ($isunknown(pixel_out[k]) || (pixel_out[k] !== expected_value)) begin
                        $display("ERROR: [relu=%0d] output[%0d] bank=%0d VALUE mismatch: expected=%0d actual=%0d",
                            active_relu, output_count, k, $signed(expected_value), $signed(pixel_out[k]));
                        errors++;
                    end
                    else begin
                        $display("PASS  [relu=%0d] output[%0d] bank=%0d col=%0d value=%0d",
                            active_relu, output_count, k, output_col, $signed(pixel_out[k]));
                    end
                end

                if (last_output_cycle != -1 && (current_cycle - last_output_cycle != 1)) begin
                    $display("ERROR: [relu=%0d] OUTPUT BUBBLE: previous_cycle=%0d current_cycle=%0d",
                        active_relu, last_output_cycle, current_cycle);
                    errors++;
                end
                last_output_cycle = current_cycle;
            end
            else begin
                $display("ERROR: [relu=%0d] Extra output detected: bank0=%0d", active_relu, $signed(pixel_out[0]));
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
        active_relu = 1'b0;

        test_kernel[0][0] = 127; test_kernel[0][1] = 127; test_kernel[0][2] = 1;
        for (int i = 3; i < NUM_TAPS; i++) test_kernel[0][i] = 0;
        test_kernel[1][0] = -127; test_kernel[1][1] = -127; test_kernel[1][2] = -1;
        for (int i = 3; i < NUM_TAPS; i++) test_kernel[1][i] = 0;

        reset_dut();
        build_image();
        calculate_expected_norelu();
        calculate_expected_relu();
        program_kernels();

        // --- Pass A: ReLU disabled -------------------------------------
        $display("");
        $display("=== PASS A: relu_enable = 0 ===");
        relu_enable  = 1'b0;
        active_relu  = 1'b0;
        output_count = 0;
        last_output_cycle = -1;
        stream_image();
        wait (done == 1'b1);
        repeat (3) @(negedge clk);
        if (output_count != TOTAL_OUTPUT_PIXELS) begin
            $display("ERROR: PASS A expected %0d outputs but received %0d", TOTAL_OUTPUT_PIXELS, output_count);
            errors++;
        end

        // --- Pass B: ReLU enabled
        $display("");
        $display("=== PASS B: relu_enable = 1 ===");
        relu_enable  = 1'b1;
        active_relu  = 1'b1;
        output_count = 0;
        last_output_cycle = -1;
        stream_image();
        wait (done == 1'b1);
        repeat (3) @(negedge clk);
        if (output_count != TOTAL_OUTPUT_PIXELS) begin
            $display("ERROR: PASS B expected %0d outputs but received %0d", TOTAL_OUTPUT_PIXELS, output_count);
            errors++;
        end

        $display("");
        $display("==============================================");
        $display("              TEST SUMMARY");
        $display("==============================================");
        $display("Errors : %0d", errors);
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
