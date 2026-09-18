module mac_array #(
    parameter int NUM_TAPS = 9  // KERNEL_SIZE * KERNEL_SIZE
)(
    input  logic [7:0]        pixel  [0:NUM_TAPS-1],
    input  logic signed [7:0] kernel [0:NUM_TAPS-1],
    output logic signed [15:0] product [0:NUM_TAPS-1]
);
    always_comb begin
        for (int i = 0; i < NUM_TAPS; i++) begin
            product[i] =
                $signed({1'b0, pixel[i]}) *
                kernel[i];
        end
    end

endmodule
