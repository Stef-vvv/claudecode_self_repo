module gin #(
    parameter DATA_WIDTH = 64, 
    parameter ROW_TAG_WIDTH = 4,
    parameter COL_TAG_WIDTH = 4,
    parameter NUM_OF_ROWS = 12,
    parameter NUM_OF_COLS = 14
)(
    input wire clk, reset,
    input wire [ROW_TAG_WIDTH-1:0] row_tag,
    input wire [COL_TAG_WIDTH-1:0] col_tag,
    input wire [ROW_TAG_WIDTH-1:0] row_id [0:NUM_OF_ROWS-1],                
    input wire [COL_TAG_WIDTH-1:0] col_id [0:NUM_OF_ROWS-1][0:NUM_OF_COLS-1], 
    input wire [DATA_WIDTH-1:0] data_in,
    input wire [0:NUM_OF_COLS-1] ready_in [0:NUM_OF_ROWS-1],
    input wire enable_in,

    output wire [DATA_WIDTH-1:0] data_out [0:NUM_OF_ROWS-1][0:NUM_OF_COLS-1],
    output wire [0:NUM_OF_COLS-1] enable_out [0:NUM_OF_ROWS-1], 
    output wire ready_out
);

    // Internal Signals
    wire [DATA_WIDTH-1:0]  row_data_out [0:NUM_OF_ROWS-1];
    wire [0:NUM_OF_ROWS-1] row_enable_out;
    wire [0:NUM_OF_ROWS-1] internal_ready;
    wire [0:NUM_OF_ROWS-1] mcc_ready;
    wire [0:NUM_OF_COLS-1] xbuses_ready [0:NUM_OF_ROWS-1];
    
    assign ready_out = &mcc_ready;
    
    // Generate MCC & X_Bus instances
    genvar i;
    generate
        for (i = 0; i < NUM_OF_ROWS; i = i + 1) begin : ROW_MCC_XBUS
            
            // ANDing to make sure that PEs are ready to recieve data
            assign internal_ready[i] = &xbuses_ready[i]; 
            
            // MCC instance for row selection
            gin_mcc #( 
                .DATA_WIDTH(DATA_WIDTH),
                .TAG_WIDTH(ROW_TAG_WIDTH)
            ) mcc_inst (
                .clk(clk),
                .reset(reset),
                .id(row_id[i]),
                .tag(row_tag),
                .data_in(data_in),
                .ready_in(internal_ready[i]),
                .enable_in(enable_in),
                .data_out(row_data_out[i]),
                .enable_out(row_enable_out[i]),
                .ready_out(mcc_ready[i])
            );
    
            // X_Bus instance for column selection
            gin_xbus #( 
                .DATA_WIDTH(DATA_WIDTH),
                .COL_TAG_WIDTH(COL_TAG_WIDTH),
                .NUM_OF_COLS(NUM_OF_COLS)
            ) xbus_inst (
                .clk(clk),
                .reset(reset),
                .col_tag(col_tag), 
                .col_id(col_id[i]),
                .data_in(row_data_out[i]),
                .ready_in(ready_in[i]),
                .enable_in(row_enable_out[i]),
                .data_out(data_out[i]),  
                .enable_out(enable_out[i]),
                .ready_out(xbuses_ready[i])
            );
        end
    endgenerate

endmodule