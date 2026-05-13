module pe_array #(
    parameter DATA_WIDTH_IFMAP     = 16, 
    parameter ROW_TAG_WIDTH_IFMAP  = 4,
    parameter COL_TAG_WIDTH_IFMAP  = 5,
    
    parameter DATA_WIDTH_FILTER    = 64, 
    parameter ROW_TAG_WIDTH_FILTER = 4,
    parameter COL_TAG_WIDTH_FILTER = 4,
    
    parameter DATA_WIDTH_PSUM      = 64, 
    parameter ROW_TAG_WIDTH_PSUM   = 4,
    parameter COL_TAG_WIDTH_PSUM   = 4,
     
    parameter NUM_OF_ROWS = 12,
    parameter NUM_OF_COLS = 14,

    parameter GIN_FIFO_DEPTH = 16,
    parameter GON_FIFO_DEPTH = 16,
    
    parameter DATA_WIDTH = 16,
    
    parameter PE_IFMAP_FIFO_DEPTH  = 4,
    parameter PE_FILTER_FIFO_DEPTH = 8,
    parameter PE_PSUM_FIFO_DEPTH   = 8,
    
    parameter W_WIDTH = 8,
    parameter S_WIDTH = 5,
    parameter F_WIDTH = 6,
    parameter U_WIDTH = 3,
    parameter n_WIDTH = 3,
    parameter p_WIDTH = 5,
    parameter q_WIDTH = 3,

    parameter IFMAP_SPAD_DEPTH  = 12,
    parameter FILTER_SPAD_DEPTH = 224,
    parameter PSUM_SPAD_DEPTH   = 24  
)(
    //---------------------------------------Control Signals--------------------------------------------\\
    input logic clk,
    input logic reset,
    
    //----------------------------------------PE Control-------------------------------------------------\\
    output logic busy [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS - 1],

    //----------------------------------Configuration Parameters-----------------------------------------\\
    input logic [W_WIDTH - 1:0] W,    
    input logic [S_WIDTH - 1:0] S,    
    input logic [F_WIDTH - 1:0] F,
    input logic [U_WIDTH - 1:0] U,
    input logic [n_WIDTH - 1:0] n,    
    input logic [p_WIDTH - 1:0] p,      
    input logic [q_WIDTH - 1:0] q,
    
    //-------------------------------------------IFMAP-----------------------------------------------------\\
    input  logic [DATA_WIDTH_IFMAP - 1:0] ifmap_to_gin,
    input  logic                          push_ifmap_to_gin,
    output logic                          ifmap_gin_fifo_full,
    
    input  logic [ROW_TAG_WIDTH_IFMAP - 1:0] ifmap_row_tag,
    input  logic [COL_TAG_WIDTH_IFMAP - 1:0] ifmap_col_tag,
    input  logic                             ifmap_tags_wr_en,
    output logic                             ifmap_tags_full,
    
    //-------------------------------------------FILTER-----------------------------------------------------\\   
    input  logic [DATA_WIDTH_FILTER - 1:0] filter_to_gin,
    input  logic                           push_filter_to_gin,
    output logic                           filter_gin_fifo_full,
    
    input  logic [ROW_TAG_WIDTH_FILTER - 1:0] filter_row_tag,
    input  logic [COL_TAG_WIDTH_FILTER - 1:0] filter_col_tag,
    input  logic                              filter_tags_wr_en,
    output logic                              filter_tags_full,
    
    //-------------------------------------------IPSUM-----------------------------------------------------\\
    input  logic [DATA_WIDTH_PSUM - 1:0] ipsum_to_gin,
    input  logic                         push_ipsum_to_gin,
    output logic                         ipsum_gin_fifo_full,
    
    input  logic [ROW_TAG_WIDTH_PSUM - 1:0] ipsum_row_tag,
    input  logic [COL_TAG_WIDTH_PSUM - 1:0] ipsum_col_tag,
    input  logic                            ipsum_tags_wr_en,
    output logic                            ipsum_tags_full,

    //-------------------------------------------OPSUM-----------------------------------------------------\\
    output logic [DATA_WIDTH_PSUM - 1:0] opsum_from_gon,
    input  logic                         pop_opsum_from_gon,
    output logic                         opsum_gon_fifo_empty,
    
    input  logic [ROW_TAG_WIDTH_PSUM - 1:0] opsum_row_tag,
    input  logic [COL_TAG_WIDTH_PSUM - 1:0] opsum_col_tag,
    input  logic                            opsum_tags_wr_en,
    output logic                            opsum_tags_full,
    
    //-----------------------------------------SCAN CHAIN---------------------------------------------------\\
    input  logic scan_en, 
    input  logic scan_in,
    output logic scan_out
);
     
    logic [DATA_WIDTH_IFMAP - 1:0] ifmap_from_gin [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS - 1]; 
    logic [0:NUM_OF_COLS - 1] push_ifmap_to_pe    [0:NUM_OF_ROWS - 1];
    logic [0:NUM_OF_COLS - 1] ifmap_pe_fifo_full  [0:NUM_OF_ROWS - 1];
    logic [0:NUM_OF_COLS - 1] ifmap_gin_ready     [0:NUM_OF_ROWS - 1];
    
    logic [DATA_WIDTH_FILTER - 1:0] filter_from_gin [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS - 1]; 
    logic [0:NUM_OF_COLS - 1] push_filter_to_pe     [0:NUM_OF_ROWS - 1];
    logic [0:NUM_OF_COLS - 1] filter_pe_fifo_full   [0:NUM_OF_ROWS - 1];
    logic [0:NUM_OF_COLS - 1] filter_gin_ready      [0:NUM_OF_ROWS - 1];
    
    logic [DATA_WIDTH_PSUM - 1:0] ipsum_from_gin        [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS-1]; 
    logic [0:NUM_OF_COLS - 1] push_ipsum_to_pe_from_gin [0:NUM_OF_ROWS - 1];
    logic [0:NUM_OF_COLS - 1] ipsum_pe_fifo_full        [0:NUM_OF_ROWS - 1];
    logic [0:NUM_OF_COLS - 1] ipsum_gin_ready           [0:NUM_OF_ROWS - 1];

    logic [DATA_WIDTH_PSUM - 1:0] opsum_from_pe        [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS-1];
    logic [0:NUM_OF_COLS - 1] pop_opsum_from_pe_to_gon [0:NUM_OF_ROWS - 1];  
    logic [0:NUM_OF_COLS - 1] opsum_pe_fifo_empty      [0:NUM_OF_ROWS - 1];
    logic [0:NUM_OF_COLS - 1] opsum_gon_ready          [0:NUM_OF_ROWS - 1];
    
    logic [0:5] scan_w; 
    logic scan_w_enable [0:NUM_OF_ROWS];
    logic scan_w_ipsum_ln_sel [0:NUM_OF_ROWS];
    logic scan_w_opsum_ln_sel [0:NUM_OF_ROWS];
    logic [0:NUM_OF_COLS - 1] enable [0:NUM_OF_ROWS - 1];
    logic [0:NUM_OF_COLS - 1] ipsum_ln_sel [0:NUM_OF_ROWS - 1];
    logic [0:NUM_OF_COLS - 1] opsum_ln_sel [0:NUM_OF_ROWS - 1];

    assign scan_w_enable[0]= scan_in;
    assign scan_w[0] = scan_w_enable[NUM_OF_ROWS];
    assign scan_w_ipsum_ln_sel[0]= scan_w[0];
    assign scan_w[1] = scan_w_ipsum_ln_sel[NUM_OF_ROWS];
    assign scan_w_opsum_ln_sel[0]= scan_w[1];
    assign scan_w[2] = scan_w_opsum_ln_sel[NUM_OF_ROWS];
        
    //------------------------------------------PE ARRAY----------------------------------------\\
    genvar i, j;
    generate
        for (i = 0; i < NUM_OF_ROWS; i = i + 1) begin : row
            scan_ff_Nbit #(.DATA_WIDTH(NUM_OF_COLS)) pe_array_enable_ff (
                .clk(clk),
                .reset(reset),
                .scan_en(scan_en),
                .scan_in(scan_w_enable[i]),
                .q(enable[i]),
                .scan_out(scan_w_enable[i+1])
            );
            
            scan_ff_Nbit #(.DATA_WIDTH(NUM_OF_COLS)) ipsum_ln_ff (
                .clk(clk),
                .reset(reset),
                .scan_en(scan_en),
                .scan_in(scan_w_ipsum_ln_sel[i]),
                .q(ipsum_ln_sel[i]),
                .scan_out(scan_w_ipsum_ln_sel[i+1])
            );
            
            scan_ff_Nbit #(.DATA_WIDTH(NUM_OF_COLS)) opsum_ln_ff (
                .clk(clk),
                .reset(reset),
                .scan_en(scan_en),
                .scan_in(scan_w_opsum_ln_sel[i]),
                .q(opsum_ln_sel[i]),
                .scan_out(scan_w_opsum_ln_sel[i+1])
            );
            
            for (j = 0; j < NUM_OF_COLS; j = j + 1) begin : col
                pe_wrapper #(
                    .DATA_WIDTH(DATA_WIDTH),
                    
                    .DATA_WIDTH_IFMAP(DATA_WIDTH_IFMAP),
                    .DATA_WIDTH_FILTER(DATA_WIDTH_FILTER),
                    .DATA_WIDTH_PSUM(DATA_WIDTH_PSUM),
                    
                    .IFMAP_FIFO_DEPTH(PE_IFMAP_FIFO_DEPTH),
                    .FILTER_FIFO_DEPTH(PE_FILTER_FIFO_DEPTH),
                    .PSUM_FIFO_DEPTH(PE_PSUM_FIFO_DEPTH),
                    
                    .W_WIDTH(W_WIDTH),
                    .S_WIDTH(S_WIDTH),
                    .F_WIDTH(F_WIDTH),
                    .U_WIDTH(U_WIDTH),
                    .n_WIDTH(n_WIDTH),
                    .p_WIDTH(p_WIDTH),
                    .q_WIDTH(q_WIDTH),
                    
                    .IFMAP_SPAD_DEPTH(IFMAP_SPAD_DEPTH),
                    .FILTER_SPAD_DEPTH(FILTER_SPAD_DEPTH),
                    .PSUM_SPAD_DEPTH(PSUM_SPAD_DEPTH)
                    ) PE_inst (
                    .clk(clk),
                    .reset(reset),
                    .busy(busy[i][j]),
                    .enable(enable[i][j]),

                    .W(W),
                    .S(S),
                    .F(F),
                    .U(U),
                    .n(n),
                    .p(p),
                    .q(q), 
                    
                    .push_ifmap(push_ifmap_to_pe[i][j]),
                    .ifmap(ifmap_from_gin[i][j]),
                    .ifmap_fifo_full(ifmap_pe_fifo_full[i][j]),

                    .push_filter(push_filter_to_pe[i][j]),
                    .filter(filter_from_gin[i][j]),
                    .filter_fifo_full(filter_pe_fifo_full[i][j]),

                    .push_ipsum(ipsum_ln_sel[i][j] ? push_ipsum_to_pe_from_gin[i][j] : ((~opsum_pe_fifo_empty[i+1][j]) & (~ipsum_pe_fifo_full[i][j]))),
                    .ipsum(ipsum_ln_sel[i][j] ? ipsum_from_gin[i][j] : opsum_from_pe[i+1][j]),
                    .ipsum_fifo_full(ipsum_pe_fifo_full[i][j]),

                    .pop_opsum(opsum_ln_sel[i][j] ? pop_opsum_from_pe_to_gon[i][j] : ((~opsum_pe_fifo_empty[i][j]) & (~ipsum_pe_fifo_full[i-1][j]))),
                    .opsum(opsum_from_pe[i][j]),
                    .opsum_fifo_empty(opsum_pe_fifo_empty[i][j])
                );
                
                assign ifmap_gin_ready [i][j] = ~ifmap_pe_fifo_full [i][j];
                assign filter_gin_ready[i][j] = ~filter_pe_fifo_full[i][j];
                assign ipsum_gin_ready [i][j] = ~ipsum_pe_fifo_full [i][j];
                assign opsum_gon_ready [i][j] = ~opsum_pe_fifo_empty[i][j];                 
            end
        end
    endgenerate
    
    //------------------------------------------------IFMAP---------------------------------------------\\
    gin_wrapper #(
        .DATA_WIDTH(DATA_WIDTH_IFMAP), 
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH_IFMAP), 
        .COL_TAG_WIDTH(COL_TAG_WIDTH_IFMAP),
        .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS),
        .GIN_DATA_FIFO_DEPTH(GIN_FIFO_DEPTH),
        .GIN_TAGS_FIFO_DEPTH(GIN_FIFO_DEPTH)
    ) ifmap_gin_inst (
        .clk(clk),
        .reset(reset),
        .row_tag(ifmap_row_tag),
        .col_tag(ifmap_col_tag),
        .ready_in(ifmap_gin_ready), 
        .data_in(ifmap_to_gin),   
        .data_out(ifmap_from_gin),
        .enable_out(push_ifmap_to_pe),    
        .tags_wr_en(ifmap_tags_wr_en),
        .tags_full(ifmap_tags_full),
        .data_wr_en(push_ifmap_to_gin),
        .data_full(ifmap_gin_fifo_full),
        .scan_en_id(scan_en),
        .scan_in_id(scan_w[2]),
        .scan_out_id(scan_w[3])
    );
  
    //------------------------------------------------FILTER---------------------------------------------\\
    gin_wrapper #(
        .DATA_WIDTH(DATA_WIDTH_FILTER), 
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH_FILTER), 
        .COL_TAG_WIDTH(COL_TAG_WIDTH_FILTER),
        .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS),
        .GIN_DATA_FIFO_DEPTH(GIN_FIFO_DEPTH),
        .GIN_TAGS_FIFO_DEPTH(GIN_FIFO_DEPTH)
    ) filter_gin_inst (
        .clk(clk),
        .reset(reset),
        .row_tag(filter_row_tag),
        .col_tag(filter_col_tag),
        .ready_in(filter_gin_ready), 
        .data_in(filter_to_gin),   
        .data_out(filter_from_gin),
        .enable_out(push_filter_to_pe),    
        .tags_wr_en(filter_tags_wr_en),
        .tags_full(filter_tags_full),
        .data_wr_en(push_filter_to_gin),
        .data_full(filter_gin_fifo_full),
        .scan_en_id(scan_en),
        .scan_in_id(scan_w[3]),
        .scan_out_id(scan_w[4])
    );
  
    //-------------------------------------------------IPSUM---------------------------------------------\\
    gin_wrapper #(
        .DATA_WIDTH(DATA_WIDTH_PSUM), 
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH_PSUM), 
        .COL_TAG_WIDTH(COL_TAG_WIDTH_PSUM),
        .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS),
        .GIN_DATA_FIFO_DEPTH(GIN_FIFO_DEPTH),
        .GIN_TAGS_FIFO_DEPTH(GIN_FIFO_DEPTH)
    ) ipsum_gin_inst (
        .clk(clk),
        .reset(reset),
        .row_tag(ipsum_row_tag),
        .col_tag(ipsum_col_tag),
        .ready_in(ipsum_gin_ready), 
        .data_in(ipsum_to_gin),   
        .data_out(ipsum_from_gin),
        .enable_out(push_ipsum_to_pe_from_gin),    
        .tags_wr_en(ipsum_tags_wr_en),
        .tags_full(ipsum_tags_full),
        .data_wr_en(push_ipsum_to_gin),
        .data_full(ipsum_gin_fifo_full),
        .scan_en_id(scan_en),
        .scan_in_id(scan_w[4]),
        .scan_out_id(scan_w[5])
    );

    //-------------------------------------------------OPSUM---------------------------------------------\\
    gon_wrapper #(
        .DATA_WIDTH(DATA_WIDTH_PSUM),
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH_PSUM),
        .COL_TAG_WIDTH(COL_TAG_WIDTH_PSUM),
        .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS),
        .GON_DATA_FIFO_DEPTH(GIN_FIFO_DEPTH),
        .GON_TAGS_FIFO_DEPTH(GON_FIFO_DEPTH)
    ) opsum_gon_inst (
        .clk(clk),
        .reset(reset),
        .row_tag(opsum_row_tag),
        .col_tag(opsum_col_tag),
        .ready_in(opsum_gon_ready),
        .data_in(opsum_from_pe),   
        .data_out(opsum_from_gon),
        .enable_out(pop_opsum_from_pe_to_gon), 
        .tags_wr_en(opsum_tags_wr_en),
        .tags_full(opsum_tags_full),
        .data_rd_en(pop_opsum_from_gon),
        .data_empty(opsum_gon_fifo_empty),
        .scan_en_id(scan_en),
        .scan_in_id(scan_w[5]),
        .scan_out_id(scan_out)
    );

endmodule