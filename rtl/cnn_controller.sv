module cnn_controller #(
    parameter int IMAGE_WIDTH  = 32,
    parameter int IMAGE_HEIGHT = 32
)(
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic pixel_valid,
    input  logic output_valid,
    output logic busy,
    output logic done
);
    localparam int TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;

    typedef enum logic [1:0] {
        IDLE,
        RUN,
        WAIT_OUTPUT,
        DONE
    } state_t;
    state_t state;
    integer pixel_count;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            pixel_count <= 0;
            busy <= 1'b0;
            done <= 1'b0;
        end
        else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    busy        <= 1'b0;
                    pixel_count <= 0;
                    if (start) begin
                        state <= RUN;
                        busy  <= 1'b1;
                    end
                end
                RUN: begin
                    busy <= 1'b1;
                    if (pixel_valid) begin
                        if (pixel_count == TOTAL_PIXELS-1) begin
                            pixel_count <= pixel_count;
                            state <= WAIT_OUTPUT;
                        end
                        else begin
                            pixel_count <= pixel_count + 1;
                        end
                    end
                end
                WAIT_OUTPUT: begin
                    busy <= 1'b1;
                    if (output_valid) begin
                        state <= DONE;
                    end
                end
                DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= IDLE;
                end
                default: begin
                    state <= IDLE;
                    busy  <= 1'b0;
                    done  <= 1'b0;
                end

            endcase

        end

    end

endmodule
