// =============================================================================
// 模块名称: noc_wrapper (NoC包装器)
// 功能描述: 在noc_controller基础上增加pass_controller进行启动/完成握手管理。
//           pass_controller接收外部start, 生成内部start_nocs脉冲,
//           等待nocs_done后将done输出给外部, 并提供busy状态。
// 数据流角色: NoC的顶层封装 —— 将外部的start脉冲转换为内部启动信号,
//           管理忙/完成状态, 向上层提供简洁的握手接口。
// 架构:
//   pass_controller (握手管理) -> noc_controller (四条并行数据通路)
// =============================================================================

module noc_wrapper
#(
    // ---- 全局尺寸参数 ----
    parameter H_WIDTH = 8,
    parameter W_WIDTH = 8,
    parameter R_WIDTH = 4,
    parameter S_WIDTH = 4,
    parameter E_WIDTH = 6,
    parameter F_WIDTH = 6,
    parameter U_WIDTH = 3,

    // ---- 分块/通道参数 ----
    parameter m_WIDTH = 8,
    parameter n_WIDTH = 3,
    parameter e_WIDTH = 8,
    parameter p_WIDTH = 5,
    parameter q_WIDTH = 3,
    parameter r_WIDTH = 2,
    parameter t_WIDTH = 3,

    // ---- 通用参数 ----
    parameter ROW_MAJOR = 1,
    parameter ADDR_WIDTH = 20,

    // ---- Ifmap FIFO ----
    parameter IFMAP_FIFO_IN_WIDTH  = 16,
    parameter IFMAP_FIFO_OUT_WIDTH = 16,
    parameter IFMAP_FIFO_DEPTH     = 16,

    // ---- Filter FIFO ----
    parameter FILTER_FIFO_IN_WIDTH  = 16,
    parameter FILTER_FIFO_OUT_WIDTH = 64,
    parameter FILTER_FIFO_DEPTH     = 16,

    // ---- Psum FIFO ----
    parameter PSUM_FIFO_IN_WIDTH  = 16,
    parameter PSUM_FIFO_OUT_WIDTH = 64,
    parameter PSUM_FIFO_DEPTH     = 16,

    // ---- 标签宽度 ----
    parameter ROW_TAG_WIDTH_IFMAP = 4,
    parameter COL_TAG_WIDTH_IFMAP = 5,
    parameter ROW_TAG_WIDTH_FILTER = 4,
    parameter COL_TAG_WIDTH_FILTER = 4,
    parameter ROW_TAG_WIDTH_PSUM = 4,
    parameter COL_TAG_WIDTH_PSUM = 4
) (
    input  clk,
    input  reset,
    input  start,          // 外部启动脉冲
    output busy,           // NoC忙碌中
    output done,           // NoC完成

    // 各维度尺寸
    input [H_WIDTH - 1:0] H,
    input [W_WIDTH - 1:0] W,
    input [R_WIDTH - 1:0] R,
    input [S_WIDTH - 1:0] S,
    input [E_WIDTH - 1:0] E,
    input [F_WIDTH - 1:0] F,
    input [U_WIDTH - 1:0] U,

    // 分块/通道参数
    input [m_WIDTH - 1:0] m,
    input [n_WIDTH - 1:0] n,
    input [e_WIDTH - 1:0] e,
    input [p_WIDTH - 1:0] p,
    input [q_WIDTH - 1:0] q,
    input [r_WIDTH - 1:0] r,
    input [t_WIDTH - 1:0] t,

    // FIFO状态输入
    input ifmap_gin_fifo_full,
    input filter_gin_fifo_full,
    input ipsum_gin_fifo_full,
    input opsum_gon_fifo_empty,

    // 全局缓冲区控制
    output ifmap_re_from_glb,
    output filter_re_from_glb,
    output ipsum_re_from_glb,
    output opsum_we_to_glb,

    // 全局缓冲区地址
    output [ADDR_WIDTH-1:0] ifmap_glb_addr,
    output [ADDR_WIDTH-1:0] filter_glb_addr,
    output [ADDR_WIDTH-1:0] ipsum_glb_addr,
    output [ADDR_WIDTH-1:0] bias_glb_addr,
    output [ADDR_WIDTH-1:0] opsum_glb_addr,

    // 标签输出
    output [ROW_TAG_WIDTH_IFMAP - 1:0] ifmap_row_tag,
    output [COL_TAG_WIDTH_IFMAP - 1:0] ifmap_col_tag,
    output [ROW_TAG_WIDTH_FILTER - 1:0] filter_row_tag,
    output [COL_TAG_WIDTH_FILTER - 1:0] filter_col_tag,
    output [ROW_TAG_WIDTH_PSUM - 1:0] ipsum_row_tag,
    output [COL_TAG_WIDTH_PSUM - 1:0] ipsum_col_tag,
    output [ROW_TAG_WIDTH_PSUM - 1:0] opsum_row_tag,
    output [COL_TAG_WIDTH_PSUM - 1:0] opsum_col_tag,

    // 全局缓冲区数据
    input [IFMAP_FIFO_IN_WIDTH - 1:0] ifmap_din,
    input [FILTER_FIFO_IN_WIDTH - 1:0] filter_din,
    input [PSUM_FIFO_IN_WIDTH - 1:0] ipsum_din,
    input [PSUM_FIFO_OUT_WIDTH - 1:0] opsum_din,

    // GIN/GON控制
    output ifmap_we_to_gin_fifo,
    output filter_we_to_gin_fifo,
    output ipsum_we_to_gin_fifo,
    output opsum_re_from_gon_fifo,

    // 标签FIFO状态
    input ifmap_tags_fifo_full,
    input filter_tags_fifo_full,
    input ipsum_tags_fifo_full,
    input opsum_tags_fifo_full,

    // 标签FIFO写使能
    output we_ifmap_tags,
    output we_filter_tags,
    output we_ipsum_tags,
    output we_opsum_tags,

    // 输出数据
    output [IFMAP_FIFO_OUT_WIDTH - 1:0] ifmap_dout,
    output [FILTER_FIFO_OUT_WIDTH - 1:0] filter_dout,
    output [PSUM_FIFO_OUT_WIDTH - 1:0] ipsum_dout,
    output [PSUM_FIFO_IN_WIDTH - 1:0]  opsum_dout
);

    // pass_controller与noc_controller之间的握手信号
    wire start_nocs;      // pass -> noc: 内部启动脉冲
    wire nocs_done;       // noc -> pass: NoC完成信号

    // ---- 握手控制器 ----
    // 管理外部start到内部start_nocs的脉冲转换,
    // 以及nocs_done到外部done的完成信号输出
    pass_controller pass_controller_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .start_nocs(start_nocs),
        .nocs_done(nocs_done),
        .busy(busy),
        .done(done)
    );

    // ---- NoC核心 ----
    // 所有信号直通到noc_controller
    noc_controller #(
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

        .IFMAP_FIFO_IN_WIDTH(IFMAP_FIFO_IN_WIDTH),
        .IFMAP_FIFO_OUT_WIDTH(IFMAP_FIFO_OUT_WIDTH),
        .IFMAP_FIFO_DEPTH(IFMAP_FIFO_DEPTH),

        .FILTER_FIFO_IN_WIDTH(FILTER_FIFO_IN_WIDTH),
        .FILTER_FIFO_OUT_WIDTH(FILTER_FIFO_OUT_WIDTH),
        .FILTER_FIFO_DEPTH(FILTER_FIFO_DEPTH),

        .PSUM_FIFO_IN_WIDTH(PSUM_FIFO_IN_WIDTH),
        .PSUM_FIFO_OUT_WIDTH(PSUM_FIFO_OUT_WIDTH),
        .PSUM_FIFO_DEPTH(PSUM_FIFO_DEPTH),

        .ROW_TAG_WIDTH_IFMAP(ROW_TAG_WIDTH_IFMAP),
        .COL_TAG_WIDTH_IFMAP(COL_TAG_WIDTH_IFMAP),
        .ROW_TAG_WIDTH_FILTER(ROW_TAG_WIDTH_FILTER),
        .COL_TAG_WIDTH_FILTER(COL_TAG_WIDTH_FILTER),
        .ROW_TAG_WIDTH_PSUM(ROW_TAG_WIDTH_PSUM),
        .COL_TAG_WIDTH_PSUM(COL_TAG_WIDTH_PSUM)
    ) noc_controller_inst (
        .clk(clk),
        .reset(reset),
        .start(start_nocs),     // 使用pass_controller生成的内部启动
        .done(nocs_done),

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

        .ifmap_din(ifmap_din),
        .filter_din(filter_din),
        .ipsum_din(ipsum_din),
        .opsum_din(opsum_din),

        .ifmap_we_to_gin_fifo(ifmap_we_to_gin_fifo),
        .filter_we_to_gin_fifo(filter_we_to_gin_fifo),
        .ipsum_we_to_gin_fifo(ipsum_we_to_gin_fifo),
        .opsum_re_from_gon_fifo(opsum_re_from_gon_fifo),

        .ifmap_tags_fifo_full(ifmap_tags_fifo_full),
        .filter_tags_fifo_full(filter_tags_fifo_full),
        .ipsum_tags_fifo_full(ipsum_tags_fifo_full),
        .opsum_tags_fifo_full(opsum_tags_fifo_full),

        .we_ifmap_tags(we_ifmap_tags),
        .we_filter_tags(we_filter_tags),
        .we_ipsum_tags(we_ipsum_tags),
        .we_opsum_tags(we_opsum_tags),

        .ifmap_dout(ifmap_dout),
        .filter_dout(filter_dout),
        .ipsum_dout(ipsum_dout),
        .opsum_dout(opsum_dout)
    );

endmodule
