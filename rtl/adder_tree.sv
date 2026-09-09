module adder_tree (
    input logic clk,
    input logic rst_n,
    input logic valid_in,
    input logic signed [15:0] product [0:8],
    output logic valid_out,
    output logic signed [31:0] sum_out
);

    logic signed [31:0] s1 [0:4];
    logic signed [31:0] s2 [0:2];

    logic valid_s1;
    logic valid_s2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s1 <= 1'b0;
            valid_s2 <= 1'b0;
            valid_out <= 1'b0;
            sum_out <= '0;
            for (int i = 0; i < 5; i++)
                s1[i] <= '0;

            for (int i = 0; i < 3; i++)
                s2[i] <= '0;
        end
        else begin
            valid_s1 <= valid_in;
            if (valid_in) begin
                s1[0] <= $signed(product[0]) + $signed(product[1]);
                s1[1] <= $signed(product[2]) + $signed(product[3]);
                s1[2] <= $signed(product[4]) + $signed(product[5]);
                s1[3] <= $signed(product[6]) + $signed(product[7]);
                s1[4] <= $signed(product[8]);
            end

            valid_s2 <= valid_s1;

            if (valid_s1) begin
                s2[0] <= s1[0] + s1[1];
                s2[1] <= s1[2] + s1[3];
                s2[2] <= s1[4];
            end

            valid_out <= valid_s2;

            if (valid_s2) begin
                sum_out <= s2[0] + s2[1] + s2[2];
            end
        end
    end
    
endmodule
