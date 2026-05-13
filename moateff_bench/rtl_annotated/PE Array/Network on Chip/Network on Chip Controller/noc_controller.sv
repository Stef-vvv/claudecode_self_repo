// =============================================================================
// 模块名称: noc_controller (NoC总控制器)
// 功能描述: 片上网络(NoC)顶层控制器, 管理四条数据通路的并行操作:
//           (1) Ifmap输入, (2) Filter输入, (3) Psum输入(ipsum), (4) Psum输出(opsum)
//           启动时同时触发所有四个子控制器, 全部完成后输出done。
// 数据流角色: NoC的总调度器 —— 接收全局start信号, 并行启动四条数据通路,
//           汇总完成信号(done = opsum_done, opsum是最后完成的)。
// 关键逻辑: D = (e << (U >> 1)) + R - U
//   这是ifmap_padding计算: 输出特征图高度 = 卷积后的有效高度
// =============================================================================

module noc_controller
#(
    // ---- 全局尺寸参数 ----
    parameter H_WIDTH = 8,    // 输出特征图高度位宽
    parameter W_WIDTH = 8,    // 输出特征图宽度位宽
    parameter R_WIDTH = 4,    // 滤波器高度位宽
    parameter S_WIDTH = 6,    // 滤波器宽度位宽
    parameter E_WIDTH = 6,    // 输入特征图高度位宽
    parameter F_WIDTH = 6,    // 输入特征图宽度位宽
    parameter U_WIDTH = 3,    // 步长位宽

    // ---- 分块/通道参数 ----
    parameter m_WIDTH = 8,    // 输出通道总数位宽
    parameter n_WIDTH = 3,    // 批大小位宽
    parameter e_WIDTH = 8,    // 特征图高度位宽
    parameter p_WIDTH = 5,    // 输出通道分块位宽
    parameter q_WIDTH = 3,    // 输入通道分块位宽
    parameter r_WIDTH = 2,    // 输入通道组数位宽
    parameter t_WIDTH = 3,    // 输出通道组数位宽

    // ---- 通用参数 ----
    parameter ROW_MAJOR = 1,
    parameter ADDR_WIDTH = 20,

    // ---- Ifmap FIFO参数 ----
    parameter IFMAP_FIFO_IN_WIDTH  = 16,
    parameter IFMAP_FIFO_OUT_WIDTH = 16,
    parameter IFMAP_FIFO_DEPTH     = 16,

    // ---- Filter FIFO参数 ----
    parameter FILTER_FIFO_IN_WIDTH  = 16,
    parameter FILTER_FIFO_OUT_WIDTH = 64,
    parameter FILTER_FIFO_DEPTH     = 16,

    // ---- Psum FIFO参数 ----
    parameter PSUM_FIFO_IN_WIDTH  = 16,
    parameter PSUM_FIFO_OUT_WIDTH = 64,
    parameter PSUM_FIFO_DEPTH     = 16,

    // ---- 标签宽度 (各通路可独立配置) ----
    parameter ROW_TAG_WIDTH_IFMAP = 4,
    parameter COL_TAG_WIDTH_IFMAP = 5,    // ifmap列标签更宽
    parameter ROW_TAG_WIDTH_FILTER = 4,
    parameter COL_TAG_WIDTH_FILTER = 4,
    parameter ROW_TAG_WIDTH_PSUM = 4,
    parameter COL_TAG_WIDTH_PSUM = 4
) (
    input  clk,
    input  reset,
    input  start,          // 全局启动
    output done,           // 全局完成 (opsum完成后置1)

    // 各维度尺寸 (广播给所有子控制器)
    input [H_WIDTH - 1:0] H,    // 输出特征图高度
    input [W_WIDTH - 1:0] W,    // 输出特征图宽度
    input [R_WIDTH - 1:0] R,    // 滤波器高度
    input [S_WIDTH - 1:0] S,    // 滤波器宽度
    input [E_WIDTH - 1:0] E,    // 输入特征图高度
    input [F_WIDTH - 1:0] F,    // 输入特征图宽度
    input [U_WIDTH - 1:0] U,    // 步长
    input [m_WIDTH - 1:0] m,    // 输出通道总数
    input [n_WIDTH - 1:0] n,    // 批大小
    input [e_WIDTH - 1:0] e,    // 特征图高度
    input [p_WIDTH - 1:0] p,    // 输出通道分块
    input [q_WIDTH - 1:0] q,    // 输入通道分块
    input [r_WIDTH - 1:0] r,    // 输入通道组数
    input [t_WIDTH - 1:0] t,    // 输出通道组数

    // 各通道完成标志
    output ifmap_done,
    output filter_done,
    output ipsum_done,
    output opsum_done,

    // 全局缓冲区地址
    output [ADDR_WIDTH-1:0] ifmap_glb_addr,
    output [ADDR_WIDTH-1:0] filter_glb_addr,
    output [ADDR_WIDTH-1:0] ipsum_glb_addr,
    output [ADDR_WIDTH-1:0] bias_glb_addr,
    output [ADDR_WIDTH-1:0] opsum_glb_addr,

    // 标签FIFO满标志 (反压输入)
    input ifmap_tags_fifo_full,
    input filter_tags_fifo_full,
    input ipsum_tags_fifo_full,
    input opsum_tags_fifo_full,

    // 标签FIFO写使能
    output we_ifmap_tags,
    output we_filter_tags,
    output we_ipsum_tags,
    output we_opsum_tags,

    // 各通路标签输出
    output [ROW_TAG_WIDTH_IFMAP - 1:0] ifmap_row_tag,
    output [COL_TAG_WIDTH_IFMAP - 1:0] ifmap_col_tag,
    output [ROW_TAG_WIDTH_FILTER - 1:0] filter_row_tag,
    output [COL_TAG_WIDTH_FILTER - 1:0] filter_col_tag,
    output [ROW_TAG_WIDTH_PSUM - 1:0] ipsum_row_tag,
    output [COL_TAG_WIDTH_PSUM - 1:0] ipsum_col_tag,
    output [ROW_TAG_WIDTH_PSUM - 1:0] opsum_row_tag,
    output [COL_TAG_WIDTH_PSUM - 1:0] opsum_col_tag,

    // 各通路FIFO满/空标志
    input ifmap_gin_fifo_full,
    input filter_gin_fifo_full,
    input ipsum_gin_fifo_full,
    input opsum_gon_fifo_empty,

    // 全局缓冲区读/写使能
    output ifmap_re_from_glb,
    output filter_re_from_glb,
    output ipsum_re_from_glb,
    output opsum_we_to_glb,

    // 全局缓冲区数据
    input [IFMAP_FIFO_IN_WIDTH - 1:0] ifmap_din,
    input [FILTER_FIFO_IN_WIDTH - 1:0] filter_din,
    input [PSUM_FIFO_IN_WIDTH - 1:0] ipsum_din,
    input [PSUM_FIFO_OUT_WIDTH - 1:0] opsum_din,

    // GIN/GON FIFO控制
    output ifmap_we_to_gin_fifo,
    output filter_we_to_gin_fifo,
    output ipsum_we_to_gin_fifo,
    output opsum_re_from_gon_fifo,

    // 输出数据总线
    output [IFMAP_FIFO_OUT_WIDTH - 1:0] ifmap_dout,
    output [FILTER_FIFO_OUT_WIDTH - 1:0] filter_dout,
    output [PSUM_FIFO_OUT_WIDTH - 1:0] ipsum_dout,
    output [PSUM_FIFO_IN_WIDTH - 1:0]  opsum_dout
);

    // 全局done: opsum完成后置1 (opsum是最后完成的数据通路)
    assign done = opsum_done;

    // D = (e << (U >> 1)) + R - U
    // 计算ifmap的等效高度D = 输出特征图高度 + 滤波器高度 - 步长
    // (e << (U>>1)): 输出特征图高度(考虑了stride)
    // + R - U: 加上滤波器高度减去步长得到输入所需高度
    logic [H_WIDTH - 1: 0] D;
    assign D = (e << (U >> 1)) + R - U;

    // ---- (1) Ifmap NoC 控制器 ----
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

        .D(D),              // 计算得到的ifmap高度
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

    // ---- (2) Filter NoC 控制器 ----
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

    // ---- (3) Psum输入 (Ipsum) NoC 控制器 ----
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

    // ---- (4) Psum输出 (Opsum) NoC 控制器 ----
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
