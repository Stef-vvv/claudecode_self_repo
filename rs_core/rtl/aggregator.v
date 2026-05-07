// Aggregator.v — Partial Sum Accumulator
//
// Receives results from PE arrays and accumulates them.
// For single PE array operation, this simply passes through the result.

module Aggregator #(
    parameter ACC_WIDTH = 16,
    parameter N_ARRAYS  = 1,
    parameter OUT_WIDTH = 16
) (
    input  wire                           clk,
    input  wire                           rst_n,

    input  wire [ACC_WIDTH*3 -1 : 0]      array_result,
    input  wire                           array_finished,

    input  wire [ACC_WIDTH*OUT_WIDTH-1:0] prev_partial,  // from BRAM
    output reg  [ACC_WIDTH*OUT_WIDTH-1:0] out_data,
    output reg                            out_valid
);

    integer i;
    reg [ACC_WIDTH-1:0] result_arr [0:2];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_data  <= 0;
            out_valid <= 1'b0;
            for (i = 0; i < 3; i = i + 1)
                result_arr[i] <= 0;
        end else begin
            out_valid <= 1'b0;

            if (array_finished) begin
                // Unpack
                for (i = 0; i < 3; i = i + 1)
                    result_arr[i] <= array_result[i*ACC_WIDTH +: ACC_WIDTH];

                // Accumulate with previous partial results
                out_data[0*ACC_WIDTH +: ACC_WIDTH] <=
                    array_result[0*ACC_WIDTH +: ACC_WIDTH] +
                    prev_partial[0*ACC_WIDTH +: ACC_WIDTH];
                out_data[1*ACC_WIDTH +: ACC_WIDTH] <=
                    array_result[1*ACC_WIDTH +: ACC_WIDTH] +
                    prev_partial[1*ACC_WIDTH +: ACC_WIDTH];
                out_data[2*ACC_WIDTH +: ACC_WIDTH] <=
                    array_result[2*ACC_WIDTH +: ACC_WIDTH] +
                    prev_partial[2*ACC_WIDTH +: ACC_WIDTH];

                out_valid <= 1'b1;
            end
        end
    end

endmodule
