module cnn_accelerator #(
    parameter int IMAGE_WIDTH  = 32,
    parameter int IMAGE_HEIGHT = 32
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    output logic busy,
    output logic done,
    input logic       pixel_valid,
    input logic [7:0] pixel_in,
    input logic              kernel_we,
    input logic [3:0]        kernel_addr,
    input logic signed [7:0] kernel_data,
    input logic relu_enable,
    output logic output_valid,
    output logic signed [15:0] pixel_out,
    output logic [$clog2(IMAGE_WIDTH)-1:0]  output_col,
    output logic [$clog2(IMAGE_HEIGHT)-1:0] output_row
);

    localparam int KERNEL_SIZE = 3;
    localparam int OUTPUT_WIDTH = IMAGE_WIDTH - KERNEL_SIZE + 1;
    localparam int OUTPUT_HEIGHT = IMAGE_HEIGHT - KERNEL_SIZE + 1;
    localparam int TOTAL_INPUT_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
    localparam int TOTAL_OUTPUT_PIXELS = OUTPUT_WIDTH * OUTPUT_HEIGHT;
    localparam int COL_WIDTH = (IMAGE_WIDTH <= 1) ? 1 : $clog2(IMAGE_WIDTH);
    localparam int ROW_WIDTH = (IMAGE_HEIGHT <= 1) ? 1 : $clog2(IMAGE_HEIGHT);
    localparam int INPUT_COUNT_WIDTH = (TOTAL_INPUT_PIXELS <= 1) ? 1 : $clog2(TOTAL_INPUT_PIXELS + 1);
    localparam int OUTPUT_COUNT_WIDTH = (TOTAL_OUTPUT_PIXELS <= 1) ? 1 : $clog2(TOTAL_OUTPUT_PIXELS + 1);
    localparam int FIFO_DEPTH      = 64;
    localparam int FIFO_ADDR_WIDTH = 6;
    localparam int FIFO_DATA_WIDTH = 16 + COL_WIDTH + ROW_WIDTH;
    localparam int FIFO_PREFILL    = 60;

    typedef enum logic [2:0] {
        S_IDLE,
        S_RUN,
        S_DRAIN,
        S_DONE
    } state_t;

    state_t state;
    logic [INPUT_COUNT_WIDTH-1:0] input_count;
    logic [OUTPUT_COUNT_WIDTH-1:0] output_count;
    logic [7:0] window [0:2][0:2];
    logic window_valid;
    logic [COL_WIDTH-1:0] window_col;
    logic [ROW_WIDTH-1:0] window_row;

    window_generator #(
        .IMAGE_WIDTH  (IMAGE_WIDTH),
        .IMAGE_HEIGHT (IMAGE_HEIGHT)
    ) u_window_generator (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_valid(
            pixel_valid && (state == S_RUN)
        ),
        .pixel_in(pixel_in),
        .window(window),
        .window_valid(window_valid),
        .window_col(window_col),
        .window_row(window_row)
    );

    logic signed [7:0] kernel [0:8];
    kernel_memory u_kernel_memory (
        .clk(clk),
        .rst_n(rst_n),
        .kernel_we(
            kernel_we && (state == S_IDLE)
        ),
        .kernel_addr(kernel_addr),
        .kernel_data(kernel_data),
        .kernel(kernel)
    );
    logic [7:0] window_flat [0:8];
    always_comb begin
        window_flat[0] = window[0][0];
        window_flat[1] = window[0][1];
        window_flat[2] = window[0][2];

        window_flat[3] = window[1][0];
        window_flat[4] = window[1][1];
        window_flat[5] = window[1][2];

        window_flat[6] = window[2][0];
        window_flat[7] = window[2][1];
        window_flat[8] = window[2][2];
    end
    logic signed [15:0] product [0:8];
    mac_array u_mac_array (
        .pixel(window_flat),
        .kernel(kernel),
        .product(product)
    );
    logic signed [31:0] accumulator;
    logic accumulator_valid;
    adder_tree u_adder_tree (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(window_valid),
        .product(product),
        .valid_out(accumulator_valid),
        .sum_out(accumulator)
    );
    logic                post_process_valid;
    logic signed [15:0]  post_process_data;
    post_process u_post_process (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(accumulator_valid),
        .accumulator(accumulator),
        .relu_enable(relu_enable),
        .valid_out(post_process_valid),
        .output_data(post_process_data)
    );
    logic [COL_WIDTH-1:0] col_pipe [0:4];
    logic [ROW_WIDTH-1:0] row_pipe [0:4];
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 5; i++) begin
                col_pipe[i] <= '0;
                row_pipe[i] <= '0;
            end
        end
        else begin
            if (window_valid) begin
                col_pipe[0] <= window_col;
                row_pipe[0] <= window_row;
            end

            col_pipe[1] <= col_pipe[0];
            col_pipe[2] <= col_pipe[1];
            col_pipe[3] <= col_pipe[2];
            col_pipe[4] <= col_pipe[3];

            row_pipe[1] <= row_pipe[0];
            row_pipe[2] <= row_pipe[1];
            row_pipe[3] <= row_pipe[2];
            row_pipe[4] <= row_pipe[3];
        end
    end
    logic [COL_WIDTH-1:0] pipe_col;
    logic [ROW_WIDTH-1:0] pipe_row;

    assign pipe_col = col_pipe[4];
    assign pipe_row = row_pipe[4];

    logic [FIFO_DATA_WIDTH-1:0] fifo_write_data;
    logic [FIFO_DATA_WIDTH-1:0] fifo_read_data;
    logic [FIFO_ADDR_WIDTH:0]   fifo_level;
    logic                       fifo_empty;
    logic                       fifo_full;
    logic                       fifo_read_en;
    logic                       fifo_started;

    assign fifo_write_data = {
        pipe_row,
        pipe_col,
        post_process_data
    };

    output_fifo #(
        .DATA_WIDTH (FIFO_DATA_WIDTH),
        .DEPTH      (FIFO_DEPTH),
        .ADDR_WIDTH (FIFO_ADDR_WIDTH)
    ) u_output_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .write_en(post_process_valid),
        .write_data(fifo_write_data),
        .read_en(fifo_read_en),
        .read_data(fifo_read_data),
        .level(fifo_level),
        .empty(fifo_empty),
        .full(fifo_full)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_started <= 1'b0;
        end
        else begin
            if (state == S_IDLE)
                fifo_started <= 1'b0;
            else if (!fifo_started && (fifo_level >= FIFO_PREFILL[FIFO_ADDR_WIDTH:0]))
                fifo_started <= 1'b1;
        end
    end

    assign fifo_read_en = fifo_started && !fifo_empty;

    logic                       output_valid_reg;
    logic signed [15:0]         pixel_out_reg;
    logic [COL_WIDTH-1:0]       output_col_reg;
    logic [ROW_WIDTH-1:0]       output_row_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_valid_reg <= 1'b0;
            pixel_out_reg    <= '0;
            output_col_reg   <= '0;
            output_row_reg   <= '0;
        end
        else begin
            output_valid_reg <= fifo_read_en;
            if (fifo_read_en) begin
                pixel_out_reg  <= $signed(fifo_read_data[15:0]);
                output_col_reg <= fifo_read_data[16 +: COL_WIDTH];
                output_row_reg <= fifo_read_data[(16 + COL_WIDTH) +: ROW_WIDTH];
            end

            else if (output_valid_reg && fifo_empty) begin
                output_col_reg <= OUTPUT_WIDTH - 1;
                output_row_reg <= OUTPUT_HEIGHT - 1;
            end
        end
    end

    assign output_valid = output_valid_reg;
    assign pixel_out    = pixel_out_reg;
    assign output_col   = output_col_reg;
    assign output_row   = output_row_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_count <= '0;
        end
        else begin
            case (state)
                S_IDLE: begin
                    input_count <= '0;
                end
                S_RUN: begin
                    if (pixel_valid && (input_count < TOTAL_INPUT_PIXELS)) begin
                        input_count <= input_count + 1'b1;
                    end
                end
                default: begin
                end
            endcase
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_count <= '0;
        end
        else begin
            case (state)
                S_IDLE: begin
                    output_count <= '0;
                end
                default: begin
                    if (output_valid && (output_count < TOTAL_OUTPUT_PIXELS)) begin
                        output_count <= output_count + 1'b1;
                    end
                end
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
        end
        else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= S_RUN;
                    end
                end
                S_RUN: begin
                    if (input_count == TOTAL_INPUT_PIXELS) begin
                        state <= S_DRAIN;
                    end
                end
                S_DRAIN: begin
                    if (output_valid && (output_count == TOTAL_OUTPUT_PIXELS - 1)) begin
                        state <= S_DONE;
                    end
                end
                S_DONE: begin
                    state <= S_IDLE;
                end
                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end
    always_comb begin
        busy = 1'b0;
        done = 1'b0;
        case (state)
            S_IDLE: begin
                busy = 1'b0;
                done = 1'b0;
            end
            S_RUN: begin
                busy = 1'b1;
                done = 1'b0;
            end
            S_DRAIN: begin
                busy = 1'b1;
                done = 1'b0;
            end
            S_DONE: begin
                busy = 1'b0;
                done = 1'b1;
            end
            default: begin
                busy = 1'b0;
                done = 1'b0;
            end
        endcase
    end

endmodule
