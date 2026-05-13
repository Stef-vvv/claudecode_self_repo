// =============================================================================
// 模块名称: ipsum_noc_controller (输入部分和NoC控制器)
// 功能描述: 管理部分和(Psum)数据从全局缓冲区到PE阵列的输入通路。
//           从全局缓冲区读取之前计算的部分和, 送入PE阵列进行累加。
//           同时生成偏置地址(bias_addr), 在首次迭代时读取偏置值。
// 数据流角色: 部分和输入数据通路控制器。
//   索引生成器: psum_index_generator(复用), 生成 n,m,e,F 四维索引
//   mapper: 映射到线性地址 ipsum_addr
//   bias_addr = idx3 (通道索引直接作为偏置地址)
//   sync_fifo: 16bit->64bit宽FIFO
//   标签生成器: psum_tag_generator
// =============================================================================

module ipsum_noc_controller
#(
    // ---- 索引维度宽度 ----
    parameter F_WIDTH = 6,    // 特征图宽度
    parameter m_WIDTH = 8,    // 输出通道总数
    parameter n_WIDTH = 3,    // 批大小
    parameter e_WIDTH = 8,    // 特征图高度
    parameter p_WIDTH = 5,    // 输出通道分块
    parameter t_WIDTH = 3,    // 输出通道组数

    // ---- FIFO参数 ----
    parameter FIFO_IN_WIDTH = 16,
    parameter FIFO_OUT_WIDTH = 64,  // 宽输出(打包)
    parameter FIFO_DEPTH = 16,

    // ---- 标签宽度 ----
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
    input [F_WIDTH - 1:0] F,    // 特征图宽度
    input [m_WIDTH - 1:0] m,    // 输出通道总数
    input [n_WIDTH - 1:0] n,    // 批大小
    input [e_WIDTH - 1:0] e,    // 特征图高度
    input [p_WIDTH - 1:0] p,    // 输出通道分块
    input [t_WIDTH - 1:0] t,    // 输出通道组数

    // 地址输出: ipsum_addr和bias_addr分别输出
    output [ADDR_WIDTH-1:0] ipsum_addr,   // 部分和数据地址
    output [ADDR_WIDTH-1:0] bias_addr,    // 偏置数据地址(通道索引直接映射)

    // 全局缓冲区接口
    output re_from_glb,
    input  [FIFO_IN_WIDTH - 1:0] din,

    // GIN FIFO接口
    input  gin_fifo_full,
    output we_to_gin_fifo,
    output [FIFO_OUT_WIDTH - 1:0] dout,

    // 标签FIFO接口
    input  tags_fifo_full,
    output we_to_tags_fifo,
    output [ROW_TAG_WIDTH - 1:0] row_tag,
    output [COL_TAG_WIDTH - 1:0] col_tag
);

    // 维度定义: dim4=n(批), dim3=m(输出通道), dim2=e(高度), dim1=F(宽度)
    localparam DIM4_WIDTH = n_WIDTH;
    localparam DIM3_WIDTH = m_WIDTH;
    localparam DIM2_WIDTH = e_WIDTH;
    localparam DIM1_WIDTH = F_WIDTH;

    wire [DIM4_WIDTH - 1:0] dim4;
    wire [DIM3_WIDTH - 1:0] dim3;
    wire [DIM2_WIDTH - 1:0] dim2;
    wire [DIM1_WIDTH - 1:0] dim1;

    assign dim4 = n;         // 批大小
    assign dim3 = m;         // 输出通道总数
    assign dim2 = e;         // 特征图高度
    assign dim1 = F;         // 特征图宽度

    // 索引信号
    localparam IDX4_WIDTH = n_WIDTH;
    localparam IDX3_WIDTH = m_WIDTH;
    localparam IDX2_WIDTH = e_WIDTH;
    localparam IDX1_WIDTH = F_WIDTH;

    wire [IDX4_WIDTH - 1:0] idx4;   // psum_index: 批索引
    wire [IDX3_WIDTH - 1:0] idx3;   // channel_index: 输出通道索引
    wire [IDX2_WIDTH - 1:0] idx2;   // row_index: 行索引
    wire [IDX1_WIDTH - 1:0] idx1;   // col_index: 列索引

    // FIFO流控
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

    // ---- Psum索引生成器 (复用) ----
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

    // ---- 地址映射器 ----
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

    // 偏置地址: 直接使用通道索引 idx3
    // 偏置数据按通道组织, 每个输出通道一个偏置值
    assign bias_addr = idx3;

    // ---- 缓冲FIFO (16->64宽) ----
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

    // ---- Psum标签生成器 ----
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
