module window_generator #(
    parameter int IMAGE_WIDTH  = 32,
    parameter int IMAGE_HEIGHT = 32
)(
    input  logic clk,
    input  logic rst_n,
    input logic       pixel_valid,
    input logic [7:0] pixel_in,
    output logic [7:0] window [0:2][0:2],
    output logic window_valid,
    output logic [$clog2(IMAGE_WIDTH)-1:0]  window_col,
    output logic [$clog2(IMAGE_HEIGHT)-1:0] window_row
);
    localparam int COL_WIDTH = (IMAGE_WIDTH <= 1) ? 1 : $clog2(IMAGE_WIDTH);
    localparam int ROW_WIDTH = (IMAGE_HEIGHT <= 1) ? 1 : $clog2(IMAGE_HEIGHT);

    logic [COL_WIDTH-1:0] current_col;
    logic [ROW_WIDTH-1:0] current_row;
    logic [7:0] previous_row;
    logic [7:0] two_rows_previous;
    logic [7:0] top_shift_0;
    logic [7:0] top_shift_1;
    logic [7:0] middle_shift_0;
    logic [7:0] middle_shift_1;
    logic [7:0] bottom_shift_0;
    logic [7:0] bottom_shift_1;

    line_buffer #(
        .IMAGE_WIDTH(IMAGE_WIDTH)
    ) u_line_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .write_en(pixel_valid),
        .column(current_col),
        .pixel_in(pixel_in),
        .previous_row(previous_row),
        .two_rows_previous(two_rows_previous)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_col <= '0;
            current_row <= '0;

            window_col <= '0;
            window_row <= '0;

            top_shift_0 <= 8'd0;
            top_shift_1 <= 8'd0;

            middle_shift_0 <= 8'd0;
            middle_shift_1 <= 8'd0;

            bottom_shift_0 <= 8'd0;
            bottom_shift_1 <= 8'd0;

            window_valid <= 1'b0;

            for (int r = 0; r < 3; r++) begin
                for (int c = 0; c < 3; c++) begin
                    window[r][c] <= 8'd0;
                end

            end

        end

        else begin
            window_valid <= 1'b0;

            if (pixel_valid) begin
                if ((current_row >= 2) && (current_col >= 2)) begin
                    window[0][0] <= top_shift_0;
                    window[0][1] <= top_shift_1;
                    window[0][2] <= two_rows_previous;

                    window[1][0] <= middle_shift_0;
                    window[1][1] <= middle_shift_1;
                    window[1][2] <= previous_row;

                    window[2][0] <= bottom_shift_0;
                    window[2][1] <= bottom_shift_1;
                    window[2][2] <= pixel_in;

                    window_valid <= 1'b1;

                    window_row <= current_row - 2;
                    window_col <= current_col - 2;
                end

                top_shift_0 <= top_shift_1;
                top_shift_1 <= two_rows_previous;

                middle_shift_0 <= middle_shift_1;
                middle_shift_1 <= previous_row;

                bottom_shift_0 <= bottom_shift_1;
                bottom_shift_1 <= pixel_in;

                if (current_col == IMAGE_WIDTH - 1) begin
                    current_col <= '0;
                    if (current_row == IMAGE_HEIGHT - 1) begin
                        current_row <= '0;
                    end
                    else begin
                        current_row <= current_row + 1'b1;
                    end
                end
                else begin
                    current_col <= current_col + 1'b1;
                end

            end

        end

    end

endmodule
