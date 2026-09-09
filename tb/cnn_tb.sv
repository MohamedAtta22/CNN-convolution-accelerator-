`timescale 1ns/1ps

module cnn_tb;

    parameter IMAGE_WIDTH  = 8;
    parameter IMAGE_HEIGHT = 8;

    logic clk;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    logic        rst_n;
    logic        start;
    logic        pixel_valid;
    logic [31:0] pixel_in;
    logic        kernel_we;
    logic [3:0]  kernel_addr;
    logic signed [7:0] kernel_data;
    logic        relu_enable;
    logic        done;
    logic [31:0] output_count;

    cnn_controller dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (start),
        .pixel_valid  (pixel_valid),
        .pixel_in     (pixel_in),
        .kernel_we    (kernel_we),
        .kernel_addr  (kernel_addr),
        .kernel_data  (kernel_data),
        .relu_enable  (relu_enable),
        .done         (done),
        .output_count (output_count)
    );

    task automatic write_kernel(
        input int addr,
        input int data
    );
        begin
            @(negedge clk);
            kernel_we   = 1'b1;
            kernel_addr = addr;
            kernel_data = data;
            @(negedge clk);
            kernel_we = 1'b0;
        end
    endtask

    initial begin
        rst_n       = 0;
        start       = 0;
        pixel_valid = 0;
        pixel_in    = 0;
        kernel_we   = 0;
        kernel_addr = 0;
        kernel_data = 0;
        relu_enable = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;

        write_kernel(0,  1);
        write_kernel(1,  0);
        write_kernel(2, -1);

        write_kernel(3,  1);
        write_kernel(4,  0);
        write_kernel(5, -1);

        write_kernel(6,  1);
        write_kernel(7,  0);
        write_kernel(8, -1);

        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;
        pixel_valid = 1;
        for (int i = 0; i < IMAGE_WIDTH * IMAGE_HEIGHT; i++) begin
            pixel_in = i;
            @(negedge clk);
        end
        pixel_valid = 0;
        pixel_in    = 0;
        wait(done);
        repeat (2) @(negedge clk);
        $display("");
        $display("===============================");
        $display("TEST COMPLETE");
        $display("Outputs = %0d", output_count);
        $display("===============================");
        $finish;
    end
endmodule
