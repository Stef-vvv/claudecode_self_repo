module processing_unit #(
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
    
    parameter IFMAP_FIFO_DEPTH  = 4,
    parameter FILTER_FIFO_DEPTH = 8,
    parameter PSUM_FIFO_DEPTH   = 8,
    
    parameter IFMAP_SPAD_DEPTH  = 12,
    parameter FILTER_SPAD_DEPTH = 224,
    parameter PSUM_SPAD_DEPTH   = 24,
    
    parameter H_WIDTH = 8,
    parameter W_WIDTH = 8,
    parameter R_WIDTH = 4,
    parameter S_WIDTH = 4,
    parameter E_WIDTH = 6,
    parameter F_WIDTH = 6,
    parameter U_WIDTH = 3,

    parameter m_WIDTH = 8,
    parameter n_WIDTH = 3,
    parameter e_WIDTH = 8,
    parameter p_WIDTH = 5,
    parameter q_WIDTH = 3,
    parameter r_WIDTH = 2,
    parameter t_WIDTH = 3,
    
    parameter ROW_MAJOR = 1,
    parameter ADDR_WIDTH = 20,
    parameter DATA_WIDTH = 16
) (
    //---------------------------------------Control Signals--------------------------------------------\\
    input  clk,
    input  reset,
    input  start,
    output busy,
    output done,

    //-------------------------------------Mapping Parameters---------------------------------------------\\
    input [H_WIDTH - 1:0] H,
    input [W_WIDTH - 1:0] W,
    input [R_WIDTH - 1:0] R,
    input [S_WIDTH - 1:0] S,
    input [E_WIDTH - 1:0] E,
    input [F_WIDTH - 1:0] F,
    input [U_WIDTH - 1:0] U,

    input [m_WIDTH - 1:0] m,
    input [n_WIDTH - 1:0] n,
    input [e_WIDTH - 1:0] e,
    input [p_WIDTH - 1:0] p,
    input [q_WIDTH - 1:0] q,
    input [r_WIDTH - 1:0] r,
    input [t_WIDTH - 1:0] t,
    
    //-------------------------------------------IFMAP-----------------------------------------------------\\
    output                    ifmap_re_from_glb,
    output [ADDR_WIDTH - 1:0] ifmap_glb_addr,
    input  [DATA_WIDTH - 1:0] ifmap_from_glb,
    
    //-------------------------------------------FILTER-----------------------------------------------------\\
    output                    filter_re_from_glb,
    output [ADDR_WIDTH - 1:0] filter_glb_addr,
    input  [DATA_WIDTH - 1:0] filter_from_glb,
    
    //--------------------------------------------PSUM-----------------------------------------------------\\
    output                    ipsum_re_from_glb,    
    output [ADDR_WIDTH - 1:0] ipsum_glb_addr,
    output [ADDR_WIDTH - 1:0] bias_glb_addr,
    input  [DATA_WIDTH - 1:0] ipsum_from_glb,
    
    output                    opsum_we_to_glb,
    output [ADDR_WIDTH - 1:0] opsum_glb_addr,
    output [DATA_WIDTH - 1:0] opsum_to_glb,
    
    //-----------------------------------------SCAN CHAIN---------------------------------------------------\\
    input  logic scan_en, 
    input  logic scan_in,
    output logic scan_out
);

    //-------------------------------------------IFMAP-----------------------------------------------------\\    
    wire [ROW_TAG_WIDTH_IFMAP - 1:0] ifmap_row_tag;
    wire [COL_TAG_WIDTH_IFMAP - 1:0] ifmap_col_tag;
    wire push_ifmap_to_gin;
    wire [DATA_WIDTH_IFMAP - 1:0] ifmap_to_gin;
    wire ifmap_gin_fifo_full;
    wire ifmap_tags_wr_en;
    wire ifmap_tags_full;
    
    //-------------------------------------------FILTER-----------------------------------------------------\\
    wire [ROW_TAG_WIDTH_FILTER - 1:0] filter_row_tag;
    wire [COL_TAG_WIDTH_FILTER - 1:0] filter_col_tag;
    wire push_filter_to_gin;
    wire [DATA_WIDTH_FILTER - 1:0] filter_to_gin;
    wire filter_gin_fifo_full;
    wire filter_tags_wr_en;
    wire filter_tags_full;
    
    //-------------------------------------------IPSUM-----------------------------------------------------\\
    wire [ROW_TAG_WIDTH_PSUM - 1:0] ipsum_row_tag;
    wire [COL_TAG_WIDTH_PSUM - 1:0] ipsum_col_tag;
    wire push_ipsum_to_gin;
    wire [DATA_WIDTH_PSUM - 1:0] ipsum_to_gin;
    wire ipsum_gin_fifo_full;
    wire ipsum_tags_wr_en;
    wire ipsum_tags_full;
    
    //-------------------------------------------OPSUM-----------------------------------------------------\\
    wire [ROW_TAG_WIDTH_PSUM - 1:0] opsum_row_tag;
    wire [COL_TAG_WIDTH_PSUM - 1:0] opsum_col_tag;
    wire pop_opsum_from_gon;
    wire [DATA_WIDTH_PSUM - 1:0] opsum_from_gon;
    wire opsum_gon_fifo_empty;
    wire opsum_tags_wr_en;
    wire opsum_tags_full;
    
    
    pe_array #(
        .DATA_WIDTH_IFMAP(DATA_WIDTH_IFMAP),
        .ROW_TAG_WIDTH_IFMAP(ROW_TAG_WIDTH_IFMAP),
        .COL_TAG_WIDTH_IFMAP(COL_TAG_WIDTH_IFMAP),

        .DATA_WIDTH_FILTER(DATA_WIDTH_FILTER),
        .ROW_TAG_WIDTH_FILTER(ROW_TAG_WIDTH_FILTER),
        .COL_TAG_WIDTH_FILTER(COL_TAG_WIDTH_FILTER),

        .DATA_WIDTH_PSUM(DATA_WIDTH_PSUM),
        .ROW_TAG_WIDTH_PSUM(ROW_TAG_WIDTH_PSUM),
        .COL_TAG_WIDTH_PSUM(COL_TAG_WIDTH_PSUM),

        .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS),

        .GIN_FIFO_DEPTH(GIN_FIFO_DEPTH),
        .GON_FIFO_DEPTH(GON_FIFO_DEPTH),

        .PE_IFMAP_FIFO_DEPTH(IFMAP_FIFO_DEPTH),
        .PE_FILTER_FIFO_DEPTH(FILTER_FIFO_DEPTH),
        .PE_PSUM_FIFO_DEPTH(PSUM_FIFO_DEPTH),

        .W_WIDTH(W_WIDTH),
        .S_WIDTH(S_WIDTH),
        .F_WIDTH(F_WIDTH),
        .U_WIDTH(U_WIDTH),
        .n_WIDTH(n_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),

        .IFMAP_SPAD_DEPTH(IFMAP_SPAD_DEPTH),
        .FILTER_SPAD_DEPTH(FILTER_SPAD_DEPTH),
        .PSUM_SPAD_DEPTH(PSUM_SPAD_DEPTH),

        .DATA_WIDTH(DATA_WIDTH)
    ) pe_array_inst (
        .clk(clk),
        .reset(reset),

        .W(W),
        .S(S),
        .F(F),
        .U(U),
        .n(n),
        .p(p),
        .q(q), 

        .ifmap_to_gin(ifmap_to_gin),
        .push_ifmap_to_gin(push_ifmap_to_gin),
        .ifmap_gin_fifo_full(ifmap_gin_fifo_full),
        .ifmap_row_tag(ifmap_row_tag),
        .ifmap_col_tag(ifmap_col_tag),
        .ifmap_tags_wr_en(ifmap_tags_wr_en),
        .ifmap_tags_full(ifmap_tags_full),

        .filter_to_gin(filter_to_gin),
        .push_filter_to_gin(push_filter_to_gin),
        .filter_gin_fifo_full(filter_gin_fifo_full),
        .filter_row_tag(filter_row_tag),
        .filter_col_tag(filter_col_tag),
        .filter_tags_wr_en(filter_tags_wr_en),
        .filter_tags_full(filter_tags_full),

        .ipsum_to_gin(ipsum_to_gin),
        .push_ipsum_to_gin(push_ipsum_to_gin),
        .ipsum_gin_fifo_full(ipsum_gin_fifo_full),
        .ipsum_row_tag(ipsum_row_tag),
        .ipsum_col_tag(ipsum_col_tag),
        .ipsum_tags_wr_en(ipsum_tags_wr_en),
        .ipsum_tags_full(ipsum_tags_full),

        .opsum_from_gon(opsum_from_gon),
        .pop_opsum_from_gon(pop_opsum_from_gon),
        .opsum_gon_fifo_empty(opsum_gon_fifo_empty),
        .opsum_row_tag(opsum_row_tag),
        .opsum_col_tag(opsum_col_tag),
        .opsum_tags_wr_en(opsum_tags_wr_en),
        .opsum_tags_full(opsum_tags_full),

        .scan_en(scan_en),
        .scan_in(scan_in),
        .scan_out(scan_out)
    );
    
    noc_wrapper #(
        .H_WIDTH(H_WIDTH),
        .W_WIDTH(W_WIDTH),
        .R_WIDTH(R_WIDTH),
        .S_WIDTH(S_WIDTH),
        .E_WIDTH(E_WIDTH),
        .F_WIDTH(F_WIDTH),
        .U_WIDTH(U_WIDTH),
    
        .m_WIDTH(m_WIDTH),
        .n_WIDTH(n_WIDTH),
        .e_WIDTH(e_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),
        .r_WIDTH(r_WIDTH),
        .t_WIDTH(t_WIDTH),
        
        .ROW_MAJOR(ROW_MAJOR),
        .ADDR_WIDTH(ADDR_WIDTH),
        
        .IFMAP_FIFO_IN_WIDTH(DATA_WIDTH_IFMAP),
        .IFMAP_FIFO_OUT_WIDTH(DATA_WIDTH_IFMAP),
        .IFMAP_FIFO_DEPTH(IFMAP_FIFO_DEPTH),
                
        .FILTER_FIFO_IN_WIDTH(DATA_WIDTH),
        .FILTER_FIFO_OUT_WIDTH(DATA_WIDTH_FILTER),
        .FILTER_FIFO_DEPTH(FILTER_FIFO_DEPTH),
        
        .PSUM_FIFO_IN_WIDTH(DATA_WIDTH),
        .PSUM_FIFO_OUT_WIDTH(DATA_WIDTH_PSUM),
        .PSUM_FIFO_DEPTH(PSUM_FIFO_DEPTH),

        .ROW_TAG_WIDTH_IFMAP(ROW_TAG_WIDTH_IFMAP),
        .COL_TAG_WIDTH_IFMAP(COL_TAG_WIDTH_IFMAP),
        .ROW_TAG_WIDTH_FILTER(ROW_TAG_WIDTH_FILTER),
        .COL_TAG_WIDTH_FILTER(COL_TAG_WIDTH_FILTER),
        .ROW_TAG_WIDTH_PSUM(ROW_TAG_WIDTH_PSUM),
        .COL_TAG_WIDTH_PSUM(COL_TAG_WIDTH_PSUM)
    ) nocs_top_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .busy(busy),
        .done(done),

        .H(H),
        .W(W),
        .R(R),
        .S(S),
        .E(E),
        .F(F),
        .U(U),
        .m(m),
        .n(n),
        .e(e),
        .p(p),
        .q(q),
        .r(r),
        .t(t),
        
        .ifmap_gin_fifo_full(ifmap_gin_fifo_full),
        .filter_gin_fifo_full(filter_gin_fifo_full),
        .ipsum_gin_fifo_full(ipsum_gin_fifo_full),
        .opsum_gon_fifo_empty(opsum_gon_fifo_empty),

        .ifmap_re_from_glb(ifmap_re_from_glb),
        .filter_re_from_glb(filter_re_from_glb),
        .ipsum_re_from_glb(ipsum_re_from_glb),
        .opsum_we_to_glb(opsum_we_to_glb),

        .ifmap_glb_addr(ifmap_glb_addr),
        .filter_glb_addr(filter_glb_addr),
        .ipsum_glb_addr(ipsum_glb_addr),
        .bias_glb_addr(bias_glb_addr),
        .opsum_glb_addr(opsum_glb_addr),
        
        .ifmap_row_tag(ifmap_row_tag),
        .ifmap_col_tag(ifmap_col_tag),
        .filter_row_tag(filter_row_tag),
        .filter_col_tag(filter_col_tag),
        .ipsum_row_tag(ipsum_row_tag),
        .ipsum_col_tag(ipsum_col_tag),
        .opsum_row_tag(opsum_row_tag),
        .opsum_col_tag(opsum_col_tag),
    
        .ifmap_din(ifmap_from_glb),
        .filter_din(filter_from_glb),
        .ipsum_din(ipsum_from_glb),
        .opsum_din(opsum_from_gon),
    
        .ifmap_we_to_gin_fifo(push_ifmap_to_gin),
        .filter_we_to_gin_fifo(push_filter_to_gin),
        .ipsum_we_to_gin_fifo(push_ipsum_to_gin),
        .opsum_re_from_gon_fifo(pop_opsum_from_gon),
        
        .ifmap_tags_fifo_full(ifmap_tags_full),
        .filter_tags_fifo_full(filter_tags_full),
        .ipsum_tags_fifo_full(ipsum_tags_full),
        .opsum_tags_fifo_full(opsum_tags_full),
        
        .we_ifmap_tags(ifmap_tags_wr_en), 
        .we_filter_tags(filter_tags_wr_en),
        .we_ipsum_tags(ipsum_tags_wr_en),
        .we_opsum_tags(opsum_tags_wr_en), 
              
        .ifmap_dout(ifmap_to_gin),
        .filter_dout(filter_to_gin),
        .ipsum_dout(ipsum_to_gin),
        .opsum_dout(opsum_to_glb)
    );

endmodule
