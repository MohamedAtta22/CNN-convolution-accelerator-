module output_fifo #(
    parameter int DATA_WIDTH = 26,
    parameter int DEPTH      = 64,
    parameter int ADDR_WIDTH = 6
)(
    input  logic clk,
    input  logic rst_n,
    input  logic                  write_en,
    input  logic [DATA_WIDTH-1:0] write_data,
    input  logic                  read_en,
    output logic [DATA_WIDTH-1:0] read_data,
    output logic [ADDR_WIDTH:0] level,
    output logic                empty,
    output logic                full
);
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    logic [ADDR_WIDTH-1:0] wr_ptr;
    logic [ADDR_WIDTH-1:0] rd_ptr;
    assign read_data = mem[rd_ptr];
    assign empty = (level == '0);
    assign full  = (level == DEPTH[ADDR_WIDTH:0]);
    logic do_write;
    logic do_read;
    assign do_write = write_en && !full;
    assign do_read  = read_en  && !empty;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            level  <= '0;
        end
        else begin
            if (do_write) begin
                mem[wr_ptr] <= write_data;
                if (wr_ptr == DEPTH - 1)
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end
            if (do_read) begin
                if (rd_ptr == DEPTH - 1)
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end
            if (do_write && !do_read)
                level <= level + 1'b1;
            else if (!do_write && do_read)
                level <= level - 1'b1;
        end

    end

endmodule
