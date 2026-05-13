module gon_xbus #(
    parameter DATA_WIDTH = 64, 
    parameter COL_TAG_WIDTH = 4,
    parameter NUM_OF_COLS = 14
)(
    input wire clk, reset,
    input wire [COL_TAG_WIDTH-1:0] col_tag,
    input wire [COL_TAG_WIDTH-1:0] col_id [0:NUM_OF_COLS-1],
    input wire [DATA_WIDTH-1:0] data_in [0:NUM_OF_COLS-1],
    input wire [0:NUM_OF_COLS-1] ready_in,
    input wire enable_in,

    inout  wire  [DATA_WIDTH-1:0] data_out,
    output wire [0:NUM_OF_COLS-1] enable_out, ready_out
);
        
    // Generate MCC instances for each column
    genvar i;
    generate
        for (i = 0; i < NUM_OF_COLS; i = i + 1) begin : MCC_INSTANCE
            gon_mcc #(
                .DATA_WIDTH(DATA_WIDTH),
                .TAG_WIDTH(COL_TAG_WIDTH)
            ) mcc_inst (
                .clk(clk),
                .reset(reset),
                .id(col_id[i]),
                .tag(col_tag),
                .data_in(data_in[i]),
                .ready_in(ready_in[i]),
                .enable_in(enable_in),
                .ready_out(ready_out[i]),
                .enable_out(enable_out[i]),
                .data_out(data_out)
            );
        end
    endgenerate
    
endmodule