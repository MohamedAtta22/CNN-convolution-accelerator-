module kernel_memory #(
    parameter  int KERNEL_SIZE  = 3,
    parameter  int NUM_KERNELS  = 1,
    localparam int NUM_TAPS     = KERNEL_SIZE * KERNEL_SIZE,
    localparam int ADDR_WIDTH   = (NUM_TAPS <= 1) ? 1 : $clog2(NUM_TAPS),
    localparam int SEL_WIDTH    = (NUM_KERNELS <= 1) ? 1 : $clog2(NUM_KERNELS)
)(
    input  logic clk,
    input  logic rst_n,
    input  logic                      kernel_we,
    input  logic [SEL_WIDTH-1:0]      kernel_sel,   // which of the NUM_KERNELS banks to write
    input  logic [ADDR_WIDTH-1:0]     kernel_addr,  // tap index within that bank (0..NUM_TAPS-1)
    input  logic signed [7:0]         kernel_data,
    output logic signed [7:0] kernel [0:NUM_KERNELS-1][0:NUM_TAPS-1]
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int k = 0; k < NUM_KERNELS; k++)
                for (int i = 0; i < NUM_TAPS; i++)
                    kernel[k][i] <= 8'sd0;
        end
        else begin
            if (kernel_we && (kernel_sel < NUM_KERNELS) && (kernel_addr < NUM_TAPS)) begin
                kernel[kernel_sel][kernel_addr] <= kernel_data;
            end
        end
    end

endmodule
