module window_generator #(
    parameter int IMAGE_WIDTH  = 32,
    parameter int IMAGE_HEIGHT = 32,
    parameter int KERNEL_SIZE  = 3
)(
    input  logic clk,
    input  logic rst_n,
    input  logic       pixel_valid,
    input  logic [7:0] pixel_in,
    output logic [7:0] window [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1],
    output logic       window_valid,
    output logic [$clog2(IMAGE_WIDTH)-1:0]  window_col,
    output logic [$clog2(IMAGE_HEIGHT)-1:0] window_row
);
    localparam int COL_WIDTH = (IMAGE_WIDTH  <= 1) ? 1 : $clog2(IMAGE_WIDTH);
    localparam int ROW_WIDTH = (IMAGE_HEIGHT <= 1) ? 1 : $clog2(IMAGE_HEIGHT);
    // TAPS = number of shift-register slots needed per row lane
    localparam int TAPS = KERNEL_SIZE - 1;

    logic [COL_WIDTH-1:0] current_col;
    logic [ROW_WIDTH-1:0] current_row;

    logic [7:0] prev_row [0:(KERNEL_SIZE > 1 ? KERNEL_SIZE-2 : 0)];

    line_buffer #(
        .IMAGE_WIDTH (IMAGE_WIDTH),
        .KERNEL_SIZE (KERNEL_SIZE)
    ) u_line_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .write_en(pixel_valid),
        .column(current_col),
        .pixel_in(pixel_in),
        .prev_row(prev_row)
    );

    logic [7:0] row_input [0:KERNEL_SIZE-1];
    always_comb begin
        for (int r = 0; r < KERNEL_SIZE - 1; r++)
            row_input[r] = prev_row[KERNEL_SIZE-2-r];
        row_input[KERNEL_SIZE-1] = pixel_in;
    end

    logic [7:0] shift_reg [0:KERNEL_SIZE-1][0:(TAPS > 0 ? TAPS-1 : 0)];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_col  <= '0;
            current_row  <= '0;
            window_col   <= '0;
            window_row   <= '0;
            window_valid <= 1'b0;
            for (int r = 0; r < KERNEL_SIZE; r++) begin
                for (int c = 0; c < KERNEL_SIZE; c++)
                    window[r][c] <= 8'd0;
                for (int t = 0; t < TAPS; t++)
                    shift_reg[r][t] <= 8'd0;
            end
        end
        else begin
            window_valid <= 1'b0;
            if (pixel_valid) begin
                if ((current_row >= KERNEL_SIZE-1) &&
                    (current_col >= KERNEL_SIZE-1)) begin

                    for (int r = 0; r < KERNEL_SIZE; r++) begin
                        for (int c = 0; c < TAPS; c++)
                            window[r][c] <= shift_reg[r][c];
                        window[r][KERNEL_SIZE-1] <= row_input[r];
                    end

                    window_col <= current_col - (KERNEL_SIZE-1);
                    window_row <= current_row - (KERNEL_SIZE-1);

                    window_valid <= 1'b1;
                end

                for (int r = 0; r < KERNEL_SIZE; r++) begin
                    for (int c = 0; c < TAPS-1; c++)
                        shift_reg[r][c] <= shift_reg[r][c+1];
                    if (TAPS > 0)
                        shift_reg[r][TAPS-1] <= row_input[r];
                end

                if (current_col == IMAGE_WIDTH-1) begin
                    current_col <= 0;
                    if (current_row == IMAGE_HEIGHT-1)
                        current_row <= 0;
                    else
                        current_row <= current_row + 1'b1;
                end
                else begin
                    current_col <= current_col + 1'b1;
                end
            end
        end
    end

endmodule
