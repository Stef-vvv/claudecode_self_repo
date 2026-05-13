module noc_controller
#(
    parameter H_WIDTH = 8,
    parameter W_WIDTH = 8,
    parameter R_WIDTH = 4,
    parameter S_WIDTH = 6,
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
    
    parameter IFMAP_FIFO_IN_WIDTH  = 16,
    parameter IFMAP_FIFO_OUT_WIDTH = 16,
    parameter IFMAP_FIFO_DEPTH     = 16,
    
    parameter FILTER_FIFO_IN_WIDTH  = 16,
    parameter FILTER_FIFO_OUT_WIDTH = 64,
    parameter FILTER_FIFO_DEPTH     = 16,
    
    parameter PSUM_FIFO_IN_WIDTH  = 16,
    parameter PSUM_FIFO_OUT_WIDTH = 64,
    parameter PSUM_FIFO_DEPTH     = 16,
    
    parameter ROW_TAG_WIDTH_IFMAP = 4,
    parameter COL_TAG_WIDTH_IFMAP = 5,
    
    parameter ROW_TAG_WIDTH_FILTER = 4,
    parameter COL_TAG_WIDTH_FILTER = 4,
    
    parameter ROW_TAG_WIDTH_PSUM = 4,
    parameter COL_TAG_WIDTH_PSUM = 4
) (
    input  clk,
    input  reset,
    input  start,
    output done,

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

    output ifmap_done,
    output filter_done,
    output ipsum_done,
    output opsum_done,

    output [ADDR_WIDTH-1:0] ifmap_glb_addr,
    output [ADDR_WIDTH-1:0] filter_glb_addr,
    output [ADDR_WIDTH-1:0] ipsum_glb_addr,
    output [ADDR_WIDTH-1:0] bias_glb_addr,
    output [ADDR_WIDTH-1:0] opsum_glb_addr,
    
    input ifmap_tags_fifo_full,
    input filter_tags_fifo_full,
    input ipsum_tags_fifo_full,
    input opsum_tags_fifo_full,
    
    output we_ifmap_tags, 
    output we_filter_tags, 
    output we_ipsum_tags, 
    output we_opsum_tags, 
    
    output [ROW_TAG_WIDTH_IFMAP - 1:0] ifmap_row_tag,
    output [COL_TAG_WIDTH_IFMAP - 1:0] ifmap_col_tag,
    output [ROW_TAG_WIDTH_FILTER - 1:0] filter_row_tag,
    output [COL_TAG_WIDTH_FILTER - 1:0] filter_col_tag,
    output [ROW_TAG_WIDTH_PSUM - 1:0] ipsum_row_tag,
    output [COL_TAG_WIDTH_PSUM - 1:0] ipsum_col_tag,
    output [ROW_TAG_WIDTH_PSUM - 1:0] opsum_row_tag,
    output [COL_TAG_WIDTH_PSUM - 1:0] opsum_col_tag,
    
    input ifmap_gin_fifo_full,
    input filter_gin_fifo_full,
    input ipsum_gin_fifo_full,
    input opsum_gon_fifo_empty,

    output ifmap_re_from_glb,
    output filter_re_from_glb,
    output ipsum_re_from_glb,
    output opsum_we_to_glb,
    
    input [IFMAP_FIFO_IN_WIDTH - 1:0] ifmap_din,
    input [FILTER_FIFO_IN_WIDTH - 1:0] filter_din,
    input [PSUM_FIFO_IN_WIDTH - 1:0] ipsum_din,
    input [PSUM_FIFO_OUT_WIDTH - 1:0] opsum_din,

    output ifmap_we_to_gin_fifo,
    output filter_we_to_gin_fifo,
    output ipsum_we_to_gin_fifo,
    output opsum_re_from_gon_fifo,  

    output [IFMAP_FIFO_OUT_WIDTH - 1:0] ifmap_dout,
    output [FILTER_FIFO_OUT_WIDTH - 1:0] filter_dout,
    output [PSUM_FIFO_OUT_WIDTH - 1:0] ipsum_dout,
    output [PSUM_FIFO_IN_WIDTH - 1:0]  opsum_dout
);
    
    assign done = opsum_done;
    
    logic [H_WIDTH - 1: 0] D;
    assign D = (e << (U >> 1)) + R - U;
    
    ifmap_noc_controller #(
        .D_WIDTH(H_WIDTH),
        .W_WIDTH(W_WIDTH),
        .U_WIDTH(U_WIDTH),
        .n_WIDTH(n_WIDTH),
        .q_WIDTH(q_WIDTH),
        .r_WIDTH(r_WIDTH),
        
        .FIFO_IN_WIDTH(IFMAP_FIFO_IN_WIDTH),
        .FIFO_OUT_WIDTH(IFMAP_FIFO_OUT_WIDTH),
        .FIFO_DEPTH(IFMAP_FIFO_DEPTH),
                
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH_IFMAP),
        .COL_TAG_WIDTH(COL_TAG_WIDTH_IFMAP),
        
        .ROW_MAJOR(ROW_MAJOR),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) ifmap_noc_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(ifmap_done),

        .D(D),
        .W(W),
        .U(U),
        .n(n),
        .q(q),
        .r(r),

        .addr(ifmap_glb_addr),

        .re_from_glb(ifmap_re_from_glb),
        .din(ifmap_din),

        .gin_fifo_full(ifmap_gin_fifo_full),
        .we_to_gin_fifo(ifmap_we_to_gin_fifo),
        .dout(ifmap_dout),
        
        .tags_fifo_full(ifmap_tags_fifo_full),
        .we_to_tags_fifo(we_ifmap_tags),
        .row_tag(ifmap_row_tag),
        .col_tag(ifmap_col_tag)
    );

    filter_noc_controller #(
        .R_WIDTH(R_WIDTH),
        .S_WIDTH(S_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),
        .r_WIDTH(r_WIDTH),
        .t_WIDTH(t_WIDTH),
        
        .FIFO_IN_WIDTH(FILTER_FIFO_IN_WIDTH),
        .FIFO_OUT_WIDTH(FILTER_FIFO_OUT_WIDTH),
        .FIFO_DEPTH(FILTER_FIFO_DEPTH),

        .ROW_TAG_WIDTH(ROW_TAG_WIDTH_FILTER),
        .COL_TAG_WIDTH(COL_TAG_WIDTH_FILTER),
        
        .ROW_MAJOR(ROW_MAJOR),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) filter_noc_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(filter_done),

        .R(R),
        .S(S),
        .p(p),
        .q(q),
        .r(r),
        .t(t),
        
        .addr(filter_glb_addr),

        .re_from_glb(filter_re_from_glb),
        .din(filter_din),
        
        .gin_fifo_full(filter_gin_fifo_full),
        .we_to_gin_fifo(filter_we_to_gin_fifo),
        .dout(filter_dout),
        
        .tags_fifo_full(filter_tags_fifo_full),
        .we_to_tags_fifo(we_filter_tags),
        .row_tag(filter_row_tag),
        .col_tag(filter_col_tag)
    );

    ipsum_noc_controller #(
        .F_WIDTH(F_WIDTH),
        .m_WIDTH(m_WIDTH),
        .n_WIDTH(n_WIDTH),
        .e_WIDTH(e_WIDTH),
        .p_WIDTH(p_WIDTH),
        .t_WIDTH(t_WIDTH),
                
        .FIFO_IN_WIDTH(PSUM_FIFO_IN_WIDTH),
        .FIFO_OUT_WIDTH(PSUM_FIFO_OUT_WIDTH),
        .FIFO_DEPTH(PSUM_FIFO_DEPTH),

        .ROW_TAG_WIDTH(ROW_TAG_WIDTH_PSUM),
        .COL_TAG_WIDTH(COL_TAG_WIDTH_PSUM),
        
        .ROW_MAJOR(ROW_MAJOR),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) ipsum_noc_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(ipsum_done),
        
        .F(F),
        .m(m),
        .n(n),
        .e(e),
        .p(p),
        .t(t),
                
        .ipsum_addr(ipsum_glb_addr),
        .bias_addr(bias_glb_addr),

        .re_from_glb(ipsum_re_from_glb),
        .din(ipsum_din),
        
        .gin_fifo_full(ipsum_gin_fifo_full),
        .we_to_gin_fifo(ipsum_we_to_gin_fifo),
        .dout(ipsum_dout),
        
        .tags_fifo_full(ipsum_tags_fifo_full),
        .we_to_tags_fifo(we_ipsum_tags),
        .row_tag(ipsum_row_tag),
        .col_tag(ipsum_col_tag)
    );
    
    opsum_noc_controller #(
        .F_WIDTH(F_WIDTH),
        .m_WIDTH(m_WIDTH),
        .n_WIDTH(n_WIDTH),
        .e_WIDTH(e_WIDTH),
        .p_WIDTH(p_WIDTH),
        .t_WIDTH(t_WIDTH),
                
        .FIFO_IN_WIDTH(PSUM_FIFO_OUT_WIDTH),
        .FIFO_OUT_WIDTH(PSUM_FIFO_IN_WIDTH),
        .FIFO_DEPTH(PSUM_FIFO_DEPTH),

        .ROW_TAG_WIDTH(ROW_TAG_WIDTH_PSUM),
        .COL_TAG_WIDTH(COL_TAG_WIDTH_PSUM),
        
        .ROW_MAJOR(ROW_MAJOR),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) opsum_noc_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .done(opsum_done),
                
        .F(F),
        .m(m),
        .n(n),
        .e(e),
        .p(p),
        .t(t),
        
        .addr(opsum_glb_addr),
        
        .re_from_gon_fifo(opsum_re_from_gon_fifo),
        .gon_fifo_empty(opsum_gon_fifo_empty),    
        .din(opsum_din),
        
        .we_to_glb(opsum_we_to_glb),
        .dout(opsum_dout),
            
        .tags_fifo_full(opsum_tags_fifo_full),
        .we_to_tags_fifo(we_opsum_tags),
        .row_tag(opsum_row_tag),
        .col_tag(opsum_col_tag)
    );
    
endmodule
