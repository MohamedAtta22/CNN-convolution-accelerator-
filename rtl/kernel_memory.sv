module kernel_memory (
    input logic clk,
    input logic rst_n,
    input logic              kernel_we,
    input logic [3:0]        kernel_addr,
    input logic signed [7:0] kernel_data,
    output logic signed [7:0] kernel [0:8]
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 9; i++)
                kernel[i] <= 8'sd0;
        end
        else begin
            if (kernel_we &&
                (kernel_addr < 9)) begin
                kernel[kernel_addr] <= kernel_data;
            end

        end

    end

endmodule
