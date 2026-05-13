// =============================================================================
// 模块名称: opsum_noc_controller (输出部分和NoC控制器)
// 功能描述: 管理部分和(Psum)数据从PE阵列回写到全局缓冲区的输出通路。
//           从GON FIFO读取PE阵列计算出的部分和, 经decollector FIFO缓冲,
//           映射地址后写入全局缓冲区。
// 数据流角色: 部分和输出数据通路控制器 (与ipsum方向相反)。
//   工作流程:
//   1. re_from_gon_fifo: 从GON的FIFO读取PE阵列输出
//   2. we_to_decollector: 写入内部缓冲FIFO
//   3. rd_from_decollector: psum_index_generator的busy驱动读出
//   4. we_to_glb: 写入全局缓冲区
// 与ipsum的关键区别:
//   - 数据流向: 从PE -> GON -> 全局缓冲区 (ipsum是从全局缓冲区 -> GIN -> PE)
//   - FIFO宽度: 64->16 (vs ipsum的16->64)
//   - decollector替代collector: "解包"FIFO
// =============================================================================

module opsum_noc_controller
#(
    // ---- 索引维度宽度 ----
    parameter F_WIDTH = 6,    // 特征图宽度
    parameter m_WIDTH = 10,   // 输出通道总数 (比ipsum的m_WIDTH=8宽)
    parameter n_WIDTH = 3,    // 批大小
    parameter e_WIDTH = 8,    // 特征图高度
    parameter p_WIDTH = 5,    // 输出通道分块
    parameter t_WIDTH = 3,    // 输出通道组数

    // ---- FIFO参数 (64->16 解包) ----
    parameter FIFO_IN_WIDTH = 64,   // 写宽度(GON输出, 打包数据)
    parameter FIFO_OUT_WIDTH = 16,  // 读宽度(写到全局缓冲区的位宽)
    parameter FIFO_DEPTH = 16,

    // ---- 标签 ----
    parameter ROW_TAG_WIDTH = 4,
    parameter COL_TAG_WIDTH = 4,

    // ---- 地址映射 ----
    parameter ROW_MAJOR = 1,
    parameter ADDR_WIDTH = 20
) (
    input  clk,
    input  reset,
    input  start,
    output done,

    // 各维度尺寸
    input [F_WIDTH - 1:0] F,
    input [m_WIDTH - 1:0] m,
    input [n_WIDTH - 1:0] n,
    input [e_WIDTH - 1:0] e,
    input [p_WIDTH - 1:0] p,
    input [t_WIDTH - 1:0] t,

    // 全局缓冲区写地址
    output [ADDR_WIDTH-1:0] addr,

    // GON FIFO接口
    output re_from_gon_fifo,         // 从GON FIFO读使能
    input  gon_fifo_empty,           // GON FIFO空标志
    input  [FIFO_IN_WIDTH - 1:0] din, // 从GON FIFO读数据

    // 全局缓冲区接口
    output we_to_glb,                 // 全局缓冲区写使能
    output [FIFO_OUT_WIDTH - 1:0] dout, // 写到全局缓冲区的数据

    // 标签FIFO接口
    input  tags_fifo_full,
    output we_to_tags_fifo,
    output [ROW_TAG_WIDTH - 1:0] row_tag,
    output [COL_TAG_WIDTH - 1:0] col_tag
);

    // 维度定义: dim4=n, dim3=m, dim2=e, dim1=F (与ipsum相同)
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

    // 索引信号
    localparam IDX4_WIDTH = n_WIDTH;
    localparam IDX3_WIDTH = m_WIDTH;
    localparam IDX2_WIDTH = e_WIDTH;
    localparam IDX1_WIDTH = F_WIDTH;

    wire [IDX4_WIDTH - 1:0] idx4;
    wire [IDX3_WIDTH - 1:0] idx3;
    wire [IDX2_WIDTH - 1:0] idx2;
    wire [IDX1_WIDTH - 1:0] idx1;

    // "解打包"FIFO (decollector) 流控
    wire decollector_full;
    wire decollector_empty;
    wire we_to_decollector;
    wire rd_from_decollector;

    // 读GON条件: GON FIFO非空 & 内部FIFO未满
    assign re_from_gon_fifo = (~gon_fifo_empty) & (~decollector_full);
    assign we_to_decollector = re_from_gon_fifo;
    // 写GLB条件: 内部FIFO读取时(rs_from_decollector)
    assign we_to_glb = rd_from_decollector;

    // ---- Psum索引生成器 (复用) ----
    // 此处索引生成器用于生成写回地址
    // busy -> rd_from_decollector -> we_to_glb
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
        .await(decollector_empty),    // FIFO空时暂停
        .busy(rd_from_decollector),   // busy驱动读FIFO
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

    // ---- 地址映射 ----
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

    // ---- 解包FIFO (64bit -> 16bit) ----
    // 将GON输出的打包数据解包为全局缓冲区的位宽
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

    // ---- Psum标签生成器 (复用) ----
    psum_tag_generator #(
        .e_WIDTH(e_WIDTH),
        .t_WIDTH(t_WIDTH),

        .ROW_TAG_WIDTH(ROW_TAG_WIDTH),
        .COL_TAG_WIDTH(COL_TAG_WIDTH)
    ) opsum_tag_generator_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .enable(~tags_fifo_full),     // 标签FIFO未满时使能
        .busy(we_to_tags_fifo),

        .e(e),
        .t(t),

        .row_tag(row_tag),
        .col_tag(col_tag)
    );

endmodule
