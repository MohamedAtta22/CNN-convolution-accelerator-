module line_buffer #(
    parameter int IMAGE_WIDTH = 32
)(
    input  logic clk,
    input  logic rst_n,
    input  logic write_en,
    input  logic [$clog2(IMAGE_WIDTH)-1:0] column,
    input  logic [7:0] pixel_in,
    output logic [7:0] previous_row,
    output logic [7:0] two_rows_previous
);
    logic [7:0] buffer_1 [0:IMAGE_WIDTH-1];
    logic [7:0] buffer_2 [0:IMAGE_WIDTH-1];

    always_comb begin
        previous_row      = buffer_1[column];
        two_rows_previous = buffer_2[column];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < IMAGE_WIDTH; i++) begin
                buffer_1[i] <= 8'd0;
                buffer_2[i] <= 8'd0;
            end
        end
        else if (write_en) begin
            buffer_2[column] <= buffer_1[column];
            buffer_1[column] <= pixel_in;
        end

    end

endmodule
