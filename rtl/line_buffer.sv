module line_buffer #(
    parameter int IMAGE_WIDTH = 32,
    parameter int KERNEL_SIZE = 3
)(
    input  logic clk,
    input  logic rst_n,
    input  logic write_en,
    input  logic [$clog2(IMAGE_WIDTH)-1:0] column,
    input  logic [7:0] pixel_in,
    output logic [7:0] prev_row [0:(KERNEL_SIZE > 1 ? KERNEL_SIZE-2 : 0)]
);
    localparam int NUM_LINES = KERNEL_SIZE - 1;

    generate
        if (KERNEL_SIZE > 1) begin : HAS_LINES
            logic [7:0] buffer [0:NUM_LINES-1][0:IMAGE_WIDTH-1];

            always_comb begin
                for (int i = 0; i < NUM_LINES; i++)
                    prev_row[i] = buffer[i][column];
            end

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (int i = 0; i < NUM_LINES; i++)
                        for (int c = 0; c < IMAGE_WIDTH; c++)
                            buffer[i][c] <= 8'd0;
                end
                else if (write_en) begin
                    for (int i = NUM_LINES - 1; i > 0; i--)
                        buffer[i][column] <= buffer[i-1][column];
                    buffer[0][column] <= pixel_in;
                end
            end
        end
        else begin : NO_LINES
            // KERNEL_SIZE == 1: no history needed at all.
            assign prev_row[0] = 8'd0;
        end
    endgenerate

endmodule
