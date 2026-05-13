module opsum_noc_controller
#( 
    parameter F_WIDTH = 6,
    parameter m_WIDTH = 10,
    parameter n_WIDTH = 3,
    parameter e_WIDTH = 8,
    parameter p_WIDTH = 5,
    parameter t_WIDTH = 3,
        
    parameter FIFO_IN_WIDTH = 64,
    parameter FIFO_OUT_WIDTH = 16,
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
    
    output [ADDR_WIDTH-1:0] addr,
    
    output re_from_gon_fifo,
    input  gon_fifo_empty,    
    input  [FIFO_IN_WIDTH - 1:0] din,
    
    output we_to_glb,
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
  
    wire decollector_full;
    wire decollector_empty;
    wire we_to_decollector;
    wire rd_from_decollector;
    
    assign re_from_gon_fifo = (~gon_fifo_empty) & (~decollector_full);
    assign we_to_decollector = re_from_gon_fifo;
    assign we_to_glb = rd_from_decollector;
    
    psum_index_generator #(
        .F_WIDTH(F_WIDTH),
        .m_WIDTH(m_WIDTH),
        .n_WIDTH(n_WIDTH),
        .e_WIDTH(e_WIDTH),
        .p_WIDTH(p_WIDTH),
        .t_WIDTH(t_WIDTH)
    ) opsum_index_generator_inst (
        .clk(clk),
        .reset(reset),
        
        .start(start),
        .await(decollector_empty),
        .busy(rd_from_decollector), 
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
        
        .addr(addr)
    );
    
    sync_fifo #(
        .R_DATA_WIDTH(FIFO_OUT_WIDTH),
        .W_DATA_WIDTH(FIFO_IN_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) opsum_fifo_inst (
        .clk(clk),
        .reset(reset),
        
        .write_request(we_to_decollector),
        .wr_data(din),  
        .read_request(rd_from_decollector), 
        .rd_data(dout),  
        
        .full_flag(decollector_full), 
        .empty_flag(decollector_empty)
    );
       
    psum_tag_generator #(
        .e_WIDTH(e_WIDTH),
        .t_WIDTH(t_WIDTH),
        
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH),
        .COL_TAG_WIDTH(COL_TAG_WIDTH)
    ) opsum_tag_generator_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .enable(~tags_fifo_full), 
        .busy(we_to_tags_fifo),
        
        .e(e),
        .t(t),
        
        .row_tag(row_tag),
        .col_tag(col_tag)
    );
    
endmodule
