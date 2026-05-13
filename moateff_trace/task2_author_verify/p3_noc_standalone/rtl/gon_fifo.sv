module gon_fifo #(
    parameter DATA_WIDTH     = 64,
    parameter ROW_TAG_WIDTH  = 4,
    parameter COL_TAG_WIDTH  = 4,
    parameter NUM_OF_ROWS    = 12,
    parameter NUM_OF_COLS    = 14,
    parameter GON_FIFO_DEPTH = 16
)(
    input wire clk,
    input wire reset,
    // input wire configure,
    
    input  wire [ROW_TAG_WIDTH-1:0] row_tag,
    input  wire [COL_TAG_WIDTH-1:0] col_tag,
    input  wire [ROW_TAG_WIDTH-1:0] row_id [0:NUM_OF_ROWS-1],                
    input  wire [COL_TAG_WIDTH-1:0] col_id [0:NUM_OF_ROWS-1][0:NUM_OF_COLS-1], 

    input  wire [DATA_WIDTH-1:0]  data_in  [0:NUM_OF_ROWS-1][0:NUM_OF_COLS-1],   
    input  wire [0:NUM_OF_COLS-1] ready_in [0:NUM_OF_ROWS-1], 
    output wire [DATA_WIDTH-1:0]  data_out,
    output wire [0:NUM_OF_COLS-1] enable_out [0:NUM_OF_ROWS-1],    
    
    input  wire tags_wr_en,
    output wire tags_full,
    input  wire data_rd_en,
    output wire data_empty
);

    wire [ROW_TAG_WIDTH+COL_TAG_WIDTH-1:0] tags_to_gon;
    wire [DATA_WIDTH-1:0] dout_from_gon;
    wire ready_out, enable_in;

    wire data_wr_en, data_full;
    wire tags_rd_en, tags_empty;
    
    assign enable_in = ready_out & ((~data_full) & (~tags_empty));
    assign data_wr_en = enable_in;
    assign tags_rd_en = enable_in;
    
    fifo_top #(
        .R_DATA_WIDTH(ROW_TAG_WIDTH + COL_TAG_WIDTH),
        .W_DATA_WIDTH(ROW_TAG_WIDTH + COL_TAG_WIDTH),
        .FIFO_DEPTH(GON_FIFO_DEPTH)
    ) tags_fifo_inst (
        .clk(clk),
        .reset(reset),
        .write_request(tags_wr_en),
        .wr_data({col_tag,row_tag}),
        .full_flag(tags_full),
        .read_request(tags_rd_en),
        .rd_data(tags_to_gon),
        .empty_flag(tags_empty)
    );

    fifo_top #(
        .R_DATA_WIDTH(DATA_WIDTH),
        .W_DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(GON_FIFO_DEPTH)
    ) data_fifo_inst (
        .clk(clk),
        .reset(reset),
        .write_request(data_wr_en),
        .wr_data(dout_from_gon),
        .full_flag(data_full),
        .read_request(data_rd_en),
        .rd_data(data_out),
        .empty_flag(data_empty)
    );
        
    gon #(
        .DATA_WIDTH(DATA_WIDTH),
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH),
        .COL_TAG_WIDTH(COL_TAG_WIDTH),
        .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS)
    ) gon_inst (
        .clk(clk),
        .reset(reset),
        .row_tag(tags_to_gon [ROW_TAG_WIDTH-1:0]),
        .col_tag(tags_to_gon [COL_TAG_WIDTH+ROW_TAG_WIDTH-1:ROW_TAG_WIDTH]),        
        .row_id(row_id),
        .col_id(col_id),
        .data_in(data_in),
        .ready_in(ready_in),
        .enable_in(enable_in),
        .data_out(dout_from_gon),
        .enable_out(enable_out),
        .ready_out(ready_out)
    );

endmodule