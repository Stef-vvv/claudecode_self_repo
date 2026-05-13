module ifmap_noc_controller
#( 
    parameter D_WIDTH = 8,
    parameter W_WIDTH = 8,
    parameter U_WIDTH = 3,
    parameter n_WIDTH = 3,
    parameter q_WIDTH = 3,
    parameter r_WIDTH = 2,
    
    parameter FIFO_IN_WIDTH = 16,
    parameter FIFO_OUT_WIDTH = 16,
    parameter FIFO_DEPTH = 16,
        
    parameter ROW_TAG_WIDTH = 4,
    parameter COL_TAG_WIDTH = 5,
    
    parameter ROW_MAJOR  = 1,
    parameter ADDR_WIDTH = 20
)(
    input  clk,
    input  reset,
    input  start,
    output done,
    
    input [D_WIDTH - 1:0] D,
    input [W_WIDTH - 1:0] W,
    input [U_WIDTH - 1:0] U,
    input [n_WIDTH - 1:0] n,
    input [q_WIDTH - 1:0] q,
    input [r_WIDTH - 1:0] r,
    
    output [ADDR_WIDTH-1:0] addr,
    
    output re_from_glb,
    input  [FIFO_IN_WIDTH - 1:0] din,
    
    input  gin_fifo_full,
    output we_to_gin_fifo,
    output [FIFO_OUT_WIDTH - 1:0] dout,
    
    input  tags_fifo_full,
    output we_to_tags_fifo,
    output [ROW_TAG_WIDTH - 1:0] row_tag,
    output [COL_TAG_WIDTH - 1:0] col_tag      
);

    localparam DIM4_WIDTH = n_WIDTH;
    localparam DIM3_WIDTH = q_WIDTH + r_WIDTH;
    localparam DIM2_WIDTH = D_WIDTH;  
    localparam DIM1_WIDTH = W_WIDTH;
    
    localparam IDX4_WIDTH = n_WIDTH;
    localparam IDX3_WIDTH = q_WIDTH + r_WIDTH;
    localparam IDX2_WIDTH = D_WIDTH;
    localparam IDX1_WIDTH = W_WIDTH;
    
    wire [DIM4_WIDTH - 1:0] dim4;
    wire [DIM3_WIDTH - 1:0] dim3;
    wire [DIM2_WIDTH - 1:0] dim2;
    wire [DIM1_WIDTH - 1:0] dim1;
    
    assign dim4 = n;
    assign dim3 = q * r;
    assign dim2 = D;
    assign dim1 = W;
    
    wire [IDX4_WIDTH - 1:0] idx4;
    wire [IDX3_WIDTH - 1:0] idx3;
    wire [IDX2_WIDTH - 1:0] idx2;
    wire [IDX1_WIDTH - 1:0] idx1;
    
    wire collector_full;
    wire collector_empty;
    wire we_to_collector;
    wire rd_from_collector;
       
    assign rd_from_collector = (~collector_empty) & (~gin_fifo_full) & (~tags_fifo_full);
    assign we_to_gin_fifo = rd_from_collector;
    assign we_to_tags_fifo = we_to_gin_fifo;
    
    flopr #(.DATA_WIDTH(1)) dff (
        .clk(~clk),
        .reset(reset),
        .d(re_from_glb),
        .q(we_to_collector)
    );
        
    ifmap_index_generator #(
        .D_WIDTH(D_WIDTH),
        .W_WIDTH(W_WIDTH),        
        .n_WIDTH(n_WIDTH),
        .q_WIDTH(q_WIDTH),
        .r_WIDTH(r_WIDTH)
    ) ifmap_index_generator_inst (
        .clk(~clk),
        .reset(reset),
        
        .start(start),
        .await(collector_full),
        .busy(re_from_glb),
        .done(done),

        .D(D),
        .W(W),
        .n(n),
        .q(q),
        .r(r),

        .ifmap_index(idx4),
        .channel_index(idx3),
        .row_index(idx2),
        .col_index(idx1)
    );
    
    mapper #(
        .DIM4_WIDTH(DIM4_WIDTH),
        .DIM3_WIDTH(DIM3_WIDTH),
        .DIM2_WIDTH(DIM2_WIDTH),
        .DIM1_WIDTH(DIM1_WIDTH),
        
        .IDX4_WIDTH(IDX4_WIDTH),
        .IDX3_WIDTH(IDX3_WIDTH),
        .IDX2_WIDTH(IDX2_WIDTH),
        .IDX1_WIDTH(IDX1_WIDTH),
        
        .ROW_MAJOR(ROW_MAJOR),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) ifmap_mapper_inst (
        .dim4(dim4),
        .dim3(dim3),
        .dim2(dim2),
        .dim1(dim1),
        
        .idx4(idx4),
        .idx3(idx3),
        .idx2(idx2),
        .idx1(idx1),
        
        .addr(addr)
    );
        
    sync_fifo #(
        .R_DATA_WIDTH(FIFO_OUT_WIDTH),
        .W_DATA_WIDTH(FIFO_IN_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) ifmap_fifo_inst (
        .clk(clk),
        .reset(reset),
        
        .write_request(we_to_collector),
        .wr_data(din),    
        .read_request(rd_from_collector),
        .rd_data(dout),    
        
        .full_flag(collector_full), 
        .empty_flag(collector_empty)
    );
        
    ifmap_tag_generator #(
        .D_WIDTH(D_WIDTH),
        .U_WIDTH(U_WIDTH),
        .r_WIDTH(r_WIDTH),
        
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH),
        .COL_TAG_WIDTH(COL_TAG_WIDTH)
    ) ifmap_tag_generator_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .enable(rd_from_collector),

        .D(D),
        .U(U),
        .r(r),

        .row_tag(row_tag),
        .col_tag(col_tag)
    );

endmodule
