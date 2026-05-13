module ipsum_noc_controller
#( 
    parameter F_WIDTH = 6,
    parameter m_WIDTH = 8,
    parameter n_WIDTH = 3,
    parameter e_WIDTH = 8,
    parameter p_WIDTH = 5,
    parameter t_WIDTH = 3,
          
    parameter FIFO_IN_WIDTH = 16,
    parameter FIFO_OUT_WIDTH = 64,
    parameter FIFO_DEPTH = 16,
      
    parameter ROW_TAG_WIDTH = 4,
    parameter COL_TAG_WIDTH = 4,

    parameter ROW_MAJOR = 1,
    parameter ADDR_WIDTH = 20
) (
    input  clk,
    input  reset,
    input  start,
    output done,
        
    input [F_WIDTH - 1:0] F,
    input [m_WIDTH - 1:0] m,
    input [n_WIDTH - 1:0] n,
    input [e_WIDTH - 1:0] e,
    input [p_WIDTH - 1:0] p,
    input [t_WIDTH - 1:0] t,
        
    output [ADDR_WIDTH-1:0] ipsum_addr,
    output [ADDR_WIDTH-1:0] bias_addr,
        
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
    localparam DIM3_WIDTH = m_WIDTH;
    localparam DIM2_WIDTH = e_WIDTH;  
    localparam DIM1_WIDTH = F_WIDTH;
    
    wire [DIM4_WIDTH - 1:0] dim4;
    wire [DIM3_WIDTH - 1:0] dim3;
    wire [DIM2_WIDTH - 1:0] dim2;
    wire [DIM1_WIDTH - 1:0] dim1;
    
    assign dim4 = n;
    assign dim3 = m;
    assign dim2 = e;
    assign dim1 = F;
    
    localparam IDX4_WIDTH = n_WIDTH;
    localparam IDX3_WIDTH = m_WIDTH;
    localparam IDX2_WIDTH = e_WIDTH;
    localparam IDX1_WIDTH = F_WIDTH;
    
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
      
    psum_index_generator #(
        .F_WIDTH(F_WIDTH),
        .m_WIDTH(m_WIDTH),
        .n_WIDTH(n_WIDTH),
        .e_WIDTH(e_WIDTH),
        .p_WIDTH(p_WIDTH),
        .t_WIDTH(t_WIDTH)
    ) ipsum_index_generator_inst (
        .clk(~clk),
        .reset(reset),
        
        .start(start),
        .await(collector_full),
        .busy(re_from_glb),
        .done(done),
                
        .F(F),
        .m(m),
        .n(n),
        .e(e),
        .p(p),
        .t(t),
        
        .psum_index(idx4),
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
    ) ipsum_mapper_inst (
        .dim4(dim4),
        .dim3(dim3),
        .dim2(dim2),
        .dim1(dim1),
        
        .idx4(idx4),
        .idx3(idx3),
        .idx2(idx2),
        .idx1(idx1),
        
        .addr(ipsum_addr)
    );
    
    assign bias_addr = idx3;
       
    sync_fifo #(
        .R_DATA_WIDTH(FIFO_OUT_WIDTH),
        .W_DATA_WIDTH(FIFO_IN_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) ipsum_fifo_inst (
        .clk(clk),
        .reset(reset),
        
        .write_request(we_to_collector),
        .wr_data(din),    
        .read_request(rd_from_collector),
        .rd_data(dout),    
        
        .full_flag(collector_full), 
        .empty_flag(collector_empty)
    );
    
    psum_tag_generator #(
        .e_WIDTH(e_WIDTH),
        .t_WIDTH(t_WIDTH),
        
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH),
        .COL_TAG_WIDTH(COL_TAG_WIDTH)
    ) ipsum_tag_generator_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .enable(rd_from_collector),
        
        .e(e),
        .t(t),
        
        .row_tag(row_tag),
        .col_tag(col_tag)
    );
    
endmodule
