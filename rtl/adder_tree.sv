module adder_tree #(
    parameter int NUM_INPUTS = 9,   // KERNEL_SIZE * KERNEL_SIZE
    parameter int IN_WIDTH   = 16,  // width of each product term
    parameter int OUT_WIDTH  = 32   // width of the final sum
)(
    input  logic clk,
    input  logic rst_n,
    input  logic valid_in,
    input  logic signed [IN_WIDTH-1:0] product [0:NUM_INPUTS-1],
    output logic valid_out,
    output logic signed [OUT_WIDTH-1:0] sum_out
);

    localparam int NUM_STAGES = (NUM_INPUTS <= 1) ? 0 : $clog2(NUM_INPUTS);

    function automatic int unsigned level_count(int unsigned n, int unsigned stage);
        int unsigned i;
        begin
            for (i = 0; i < stage; i++)
                n = (n + 1) / 2;
            level_count = n;
        end
    endfunction

    generate
        if (NUM_STAGES == 0) begin : PASSTHROUGH
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    valid_out <= 1'b0;
                    sum_out   <= '0;
                end
                else begin
                    valid_out <= valid_in;
                    if (valid_in)
                        sum_out <= (NUM_INPUTS == 1) ? product[0] : '0;
                end
            end
        end
        else begin : TREE
            genvar g;
            for (g = 0; g < NUM_STAGES; g++) begin : STAGE
                localparam int IN_COUNT  = level_count(NUM_INPUTS, g);
                localparam int OUT_COUNT = (IN_COUNT + 1) / 2;

                logic valid;
                logic signed [OUT_WIDTH-1:0] data [0:OUT_COUNT-1];

                if (g == 0) begin : SRC
                    always_ff @(posedge clk or negedge rst_n) begin
                        if (!rst_n) begin
                            valid <= 1'b0;
                            for (int i = 0; i < OUT_COUNT; i++)
                                data[i] <= '0;
                        end
                        else begin
                            valid <= valid_in;
                            if (valid_in) begin
                                for (int i = 0; i < OUT_COUNT; i++) begin
                                    if (2*i + 1 < IN_COUNT)
                                        data[i] <= product[2*i] + product[2*i+1];
                                    else
                                        data[i] <= OUT_WIDTH'(product[2*i]);
                                end
                            end
                        end
                    end
                end
                else begin : SRC
                    always_ff @(posedge clk or negedge rst_n) begin
                        if (!rst_n) begin
                            valid <= 1'b0;
                            for (int i = 0; i < OUT_COUNT; i++)
                                data[i] <= '0;
                        end
                        else begin
                            valid <= STAGE[g-1].valid;
                            if (STAGE[g-1].valid) begin
                                for (int i = 0; i < OUT_COUNT; i++) begin
                                    if (2*i + 1 < IN_COUNT)
                                        data[i] <= STAGE[g-1].data[2*i] + STAGE[g-1].data[2*i+1];
                                    else
                                        data[i] <= STAGE[g-1].data[2*i];
                                end
                            end
                        end
                    end
                end
            end

            assign valid_out = STAGE[NUM_STAGES-1].valid;
            assign sum_out    = STAGE[NUM_STAGES-1].data[0];
        end
    endgenerate

endmodule
