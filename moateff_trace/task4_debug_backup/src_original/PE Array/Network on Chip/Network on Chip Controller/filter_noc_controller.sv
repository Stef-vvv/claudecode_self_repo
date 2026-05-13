module filter_noc_controller
#( 
    parameter R_WIDTH = 4,
    parameter S_WIDTH = 6,
    parameter p_WIDTH = 5,
    parameter q_WIDTH = 3,
    parameter r_WIDTH = 2,
    parameter t_WIDTH = 3,
    
    parameter FIFO_IN_WIDTH = 16,
    parameter FIFO_OUT_WIDTH = 64,
    parameter FIFO_DEPTH = 16,
      
    parameter ROW_TAG_WIDTH = 4,
    parameter COL_TAG_WIDTH = 4,
    
    parameter ROW_MAJOR  = 1,
    parameter ADDR_WIDTH = 20
) (
    input  clk,
    input  reset,
    input  start,
    output done,
    
    input [R_WIDTH - 1:0] R,
    input [S_WIDTH - 1:0] S,
    input [p_WIDTH - 1:0] p,
    input [q_WIDTH - 1:0] q,
    input [r_WIDTH - 1:0] r,
    input [t_WIDTH - 1:0] t,
    

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

    localparam DIM4_WIDTH = p_WIDTH + t_WIDTH;
    localparam DIM3_WIDTH = q_WIDTH + r_WIDTH;
    localparam DIM2_WIDTH = R_WIDTH;  
    localparam DIM1_WIDTH = S_WIDTH;
    
    localparam IDX4_WIDTH = p_WIDTH + t_WIDTH;
    localparam IDX3_WIDTH = q_WIDTH + r_WIDTH;
    localparam IDX2_WIDTH = R_WIDTH;
    localparam IDX1_WIDTH = S_WIDTH;
    
    wire [DIM4_WIDTH - 1:0] dim4;
    wire [DIM3_WIDTH - 1:0] dim3;
    wire [DIM2_WIDTH - 1:0] dim2;
    wire [DIM1_WIDTH - 1:0] dim1;
    
    assign dim4 = p * t;
    assign dim3 = q * r;
    assign dim2 = R;
    assign dim1 = S;
    
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
        
    filter_index_generator #(
        .R_WIDTH(R_WIDTH),
        .S_WIDTH(S_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),
        .r_WIDTH(r_WIDTH),
        .t_WIDTH(t_WIDTH)
    ) filter_index_generator_inst (
        .clk(~clk),
        .reset(reset),
        
        .start(start),
        .await(collector_full),
        .busy(re_from_glb),
        .done(done),
        
        .R(R),
        .S(S),
        .p(p),
        .q(q),
        .r(r),
        .t(t),
        
        .filter_index(idx4),
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
    ) filter_mapper_inst (
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
    ) filter_fifo_inst (
        .clk(clk),
        .reset(reset),
        
        .write_request(we_to_collector),
        .wr_data(din),    
        .read_request(rd_from_collector),
        .rd_data(dout),    
        
        .full_flag(collector_full), 
        .empty_flag(collector_empty)
    );
    
    filter_tag_generator #(
        .R_WIDTH(R_WIDTH),
        .r_WIDTH(r_WIDTH),
        .t_WIDTH(t_WIDTH),
        
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH),
        .COL_TAG_WIDTH(COL_TAG_WIDTH)
    ) filter_tag_generator_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .enable(rd_from_collector),
        
        .R(R),
        .r(r),
        .t(t),
        
        .row_tag(row_tag),
        .col_tag(col_tag)
    );
    
endmodule
