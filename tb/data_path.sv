`timescale 1ns/1ps

module datapath_tb;

    logic clk;
    logic rst_n;
    logic [7:0] pixel [0:8];
    logic signed [7:0] kernel [0:8];
    logic signed [15:0] product [0:8];
    logic valid_in;
    logic valid_sum;
    logic signed [31:0] sum;
    logic valid_out;
    logic signed [15:0] output_data;
    logic relu_enable;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    mac_array u_mac (
        .pixel(pixel),
        .kernel(kernel),
        .product(product)
    );

    adder_tree u_adder (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),
        .product(product),
        .valid_out(valid_sum),
        .sum_out(sum)
    );

    post_process u_post (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_sum),
        .accumulator(sum),
        .relu_enable(relu_enable),
        .valid_out(valid_out),
        .output_data(output_data)
    );

    initial begin
        rst_n = 0;
        valid_in = 0;
        relu_enable = 0;
        for (int i = 0; i < 9; i++) begin
            pixel[i]  = 0;
            kernel[i] = 0;
        end

        repeat (2) @(negedge clk);
        rst_n = 1;

        pixel[0] = 1;
        pixel[1] = 2;
        pixel[2] = 3;

        pixel[3] = 4;
        pixel[4] = 5;
        pixel[5] = 6;

        pixel[6] = 7;
        pixel[7] = 8;
        pixel[8] = 9;    

        kernel[0] =  1;
        kernel[1] =  0;
        kernel[2] = -1;

        kernel[3] =  1;
        kernel[4] =  0;
        kernel[5] = -1;

        kernel[6] =  1;
        kernel[7] =  0;
        kernel[8] = -1;

        @(negedge clk);
        valid_in = 1;
        @(negedge clk);
        valid_in = 0;

        repeat (6) @(negedge clk);

        $display("");
        $display("==============================");
        $display("Expected sum = -6");
        $display("Actual sum   = %0d", sum);
        $display("==============================");
        $finish;

    end

    always @(posedge clk) begin
        if (valid_out) begin
            #1;
            $display(
                "OUTPUT = %0d",
                $signed(output_data)
            );

        end

    end

endmodule
