module gin_xbus #(
    parameter int DATA_WIDTH = 64, 
    parameter int COL_TAG_WIDTH = 4,
    parameter int NUM_OF_COLS = 14
) (
    input logic [DATA_WIDTH - 1:0] data_in,
    input logic [COL_TAG_WIDTH - 1:0] col_tag,

    input logic [0:NUM_OF_COLS - 1] ready_in,
    input logic clk, reset, enable_in,
    input logic scan_en_id, scan_in_id,

    output logic [DATA_WIDTH - 1:0] data_out [0:NUM_OF_COLS - 1],
    output logic [0:NUM_OF_COLS - 1] enable_out, ready_out,
    output logic scan_out_id
);

    wire [0 : NUM_OF_COLS] scan_w;
    assign scan_w[0] = scan_in_id;
    assign scan_out_id = scan_w[NUM_OF_COLS];
    
    // Generate MCC instances for each column
    genvar i;
    generate
        for (i = 0; i < NUM_OF_COLS; i = i + 1) begin : MCC_INSTANCE
            gin_mcc #(
                .DATA_WIDTH(DATA_WIDTH),
                .TAG_WIDTH(COL_TAG_WIDTH)
            ) mcc_inst (
                .data_in(data_in),
                .tag(col_tag),
                .clk(clk),
                .reset(reset),
                .ready_in(ready_in[i]),
                .enable_in(enable_in),
                .scan_en_id(scan_en_id),//
                .scan_in_id(scan_w[i]),//
                .ready_out(ready_out[i]),
                .enable_out(enable_out[i]),
                .data_out(data_out[i]),
                .scan_out_id(scan_w[i+1])//
            );
        end
    endgenerate

endmodule