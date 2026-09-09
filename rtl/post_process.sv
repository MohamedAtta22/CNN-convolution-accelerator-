module post_process (
    input logic clk,
    input logic rst_n,
    input logic valid_in,
    input logic signed [31:0] accumulator,
    input logic relu_enable,
    output logic valid_out,
    output logic signed [15:0] output_data
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out   <= 1'b0;
            output_data <= 16'sd0;
        end
        else begin
            valid_out <= valid_in;
            if (valid_in) begin
                if (relu_enable && accumulator < 0) begin
                    output_data <= 16'sd0;
                end
                else if (accumulator > 32'sd32767) begin
                    output_data <= 16'sh7FFF;
                end
                else if (accumulator < -32'sd32768) begin
                    output_data <= 16'sh8000;
                end
                else begin
                    output_data <= accumulator[15:0];
                end
            end
        end

    end

endmodule
