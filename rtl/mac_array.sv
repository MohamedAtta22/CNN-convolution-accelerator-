module mac_array (
    input logic [7:0] pixel [0:8],
    input logic signed [7:0] kernel [0:8],
    output logic signed [15:0] product [0:8]
);
    always_comb begin
        for (int i = 0; i < 9; i++) begin
            product[i] =
                $signed({1'b0, pixel[i]}) *
                kernel[i];
        end

    end

endmodule
