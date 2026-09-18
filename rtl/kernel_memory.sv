module kernel_memory #(
    parameter  int KERNEL_SIZE = 3,
    localparam int NUM_TAPS    = KERNEL_SIZE * KERNEL_SIZE,
    localparam int ADDR_WIDTH  = (NUM_TAPS <= 1) ? 1 : $clog2(NUM_TAPS)
)(
    input  logic clk,
    input  logic rst_n,
    input  logic                       kernel_we,
    input  logic [ADDR_WIDTH-1:0]      kernel_addr,
    input  logic signed [7:0]          kernel_data,
    output logic signed [7:0] kernel [0:NUM_TAPS-1]
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_TAPS; i++)
                kernel[i] <= 8'sd0;
        end
        else begin
            if (kernel_we && (kernel_addr < NUM_TAPS)) begin
                kernel[kernel_addr] <= kernel_data;
            end
        end
    end

endmodule
