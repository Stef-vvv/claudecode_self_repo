module gin_wrapper
#(
    parameter DATA_WIDTH    = 64,
    parameter ROW_TAG_WIDTH = 4,
    parameter COL_TAG_WIDTH = 4,
    parameter NUM_OF_ROWS   = 12,
    parameter NUM_OF_COLS   = 14,
    parameter GIN_DATA_FIFO_DEPTH = 4096,
    parameter GIN_TAGS_FIFO_DEPTH = 4096
)(
    input clk,
    input reset,

    // input [ROW_TAG_WIDTH - 1:0] id_row   [0:NUM_OF_ROWS - 1],                
    // input [COL_TAG_WIDTH - 1:0] id_col   [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS - 1],
    input [ROW_TAG_WIDTH - 1:0] row_tag,
    input [COL_TAG_WIDTH - 1:0] col_tag,

    input  [0:NUM_OF_COLS - 1] ready_in [0:NUM_OF_ROWS - 1],
    input  [DATA_WIDTH - 1:0]  data_in,   
    output [DATA_WIDTH - 1:0]  data_out   [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS - 1],
    output [0:NUM_OF_COLS - 1] enable_out [0:NUM_OF_ROWS - 1],
    
    input tags_wr_en,
    output tags_full,
    
    input data_wr_en,
    output data_full,
    
    input  scan_en_id, scan_in_id,
    output scan_out_id
);
    wire [ROW_TAG_WIDTH + COL_TAG_WIDTH - 1 : 0] tags_to_gin;
    wire [DATA_WIDTH - 1:0] data_from_fifo_to_gin;
    wire ready_out, enable_in;

    wire data_rd_en, data_empty;
    wire tags_rd_en, tags_empty;

    assign enable_in = ready_out & ((~data_empty) & (~tags_empty));
    assign data_rd_en = enable_in;
    assign tags_rd_en = enable_in;
    
    sync_fifo #(
        .R_DATA_WIDTH(ROW_TAG_WIDTH + COL_TAG_WIDTH),
        .W_DATA_WIDTH(ROW_TAG_WIDTH + COL_TAG_WIDTH),
        .FIFO_DEPTH(GIN_TAGS_FIFO_DEPTH)
    ) tags_fifo_inst (
        .clk(clk),
        .reset(reset),

        .write_request(tags_wr_en),
        .wr_data({col_tag,row_tag}),
        .full_flag(tags_full),
        
        .read_request(tags_rd_en),
        .rd_data(tags_to_gin),
        .empty_flag(tags_empty)
    );
    
    sync_fifo #(
        .R_DATA_WIDTH(DATA_WIDTH),
        .W_DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(GIN_DATA_FIFO_DEPTH)
    ) data_fifo_inst (
        .clk(clk),
        .reset(reset),

        .write_request(data_wr_en),
        .wr_data(data_in),
        .full_flag(data_full),
        
        .read_request(data_rd_en),
        .rd_data(data_from_fifo_to_gin),
        .empty_flag(data_empty)
    );
        
    gin #(
        .DATA_WIDTH(DATA_WIDTH),
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH),
        .COL_TAG_WIDTH(COL_TAG_WIDTH),
        .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS)
    ) gin_inst (
        .clk(clk),
        .reset(reset),
        .enable_in(enable_in),
        
        .data_in(data_from_fifo_to_gin),
        .row_tag(tags_to_gin [ROW_TAG_WIDTH - 1:0]),
        .col_tag(tags_to_gin [COL_TAG_WIDTH + ROW_TAG_WIDTH - 1:ROW_TAG_WIDTH]),
        
        .ready_in(ready_in),
        .scan_en_id(scan_en_id),
        .scan_in_id(scan_in_id),

        .data_out(data_out),
        .enable_out(enable_out),
        .ready_out(ready_out),
        .scan_out_id(scan_out_id)
    );
        
endmodule