// =============================================================================
// 模块名称: ifmap_noc_controller (输入特征图NoC控制器)
// 功能描述: 管理输入特征图(Ifmap)数据从全局缓冲区到PE阵列的完整数据通路。
//           包含: 索引生成器 -> 地址映射器 -> 全局缓冲区读 -> FIFO缓冲 -> 标签生成
// 数据流角色: Ifmap数据通路的总控制器。
//   索引生成器: 生成4维索引: ifmap_index(n), channel_index(q+r*q), row_index(D), col_index(W)
//   mapper: 将多维索引映射为线性地址 addr
//   sync_fifo: 缓冲从全局缓冲区读出的数据(16bit->16bit, 同宽)
//   tag_generator: 同步生成数据路由标签(row_tag, col_tag, col_tag比filter宽1位)
// 与filter_noc_controller的关键区别:
//   1. 维度不同: D,W 替代 R,S; n 替代 p*t
//   2. FIFO宽度: 16->16 (vs filter的16->64)
//   3. COL_TAG_WIDTH=5 (vs filter的4)
// =============================================================================

module ifmap_noc_controller
#(
    // ---- 索引维度宽度 ----
    parameter D_WIDTH = 8,    // Ifmap高度
    parameter W_WIDTH = 8,    // Ifmap宽度
    parameter U_WIDTH = 3,    // 步长参数
    parameter n_WIDTH = 3,    // 批大小
    parameter q_WIDTH = 3,    // 输入通道分块
    parameter r_WIDTH = 2,    // 通道组数

    // ---- FIFO参数 ----
    parameter FIFO_IN_WIDTH = 16,   // 写宽度(全局缓冲区数据宽度)
    parameter FIFO_OUT_WIDTH = 16,  // 读宽度(与写同宽, 不做打包)
    parameter FIFO_DEPTH = 16,

    // ---- 标签宽度 ----
    parameter ROW_TAG_WIDTH = 4,
    parameter COL_TAG_WIDTH = 5,    // ifmap需要更宽的列标签

    // ---- 地址映射 ----
    parameter ROW_MAJOR  = 1,
    parameter ADDR_WIDTH = 20
)(
    input  clk,
    input  reset,
    input  start,          // 启动
    output done,           // 完成

    // 各维度尺寸
    input [D_WIDTH - 1:0] D,    // Ifmap高度
    input [W_WIDTH - 1:0] W,    // Ifmap宽度
    input [U_WIDTH - 1:0] U,    // 步长
    input [n_WIDTH - 1:0] n,    // 批大小
    input [q_WIDTH - 1:0] q,    // 输入通道分块
    input [r_WIDTH - 1:0] r,    // 通道组数

    // 线性地址输出
    output [ADDR_WIDTH-1:0] addr,

    // 全局缓冲区接口
    output re_from_glb,              // 读使能
    input  [FIFO_IN_WIDTH - 1:0] din, // 读数据输入

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

    // ---- 维度定义 ----
    // dim4=n(批), dim3=q*r(输入通道总数), dim2=D(高度), dim1=W(宽度)
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

    assign dim4 = n;         // 批大小
    assign dim3 = q * r;     // 输入通道总数 = q * r
    assign dim2 = D;         // Ifmap高度
    assign dim1 = W;         // Ifmap宽度

    // 索引信号
    wire [IDX4_WIDTH - 1:0] idx4;   // ifmap_index: 批索引
    wire [IDX3_WIDTH - 1:0] idx3;   // channel_index: 通道索引
    wire [IDX2_WIDTH - 1:0] idx2;   // row_index: 行索引
    wire [IDX1_WIDTH - 1:0] idx1;   // col_index: 列索引

    // ---- FIFO流控 ----
    wire collector_full;
    wire collector_empty;
    wire we_to_collector;
    wire rd_from_collector;

    // 读出条件: FIFO非空 & 下游GIN不满 & 标签FIFO不满
    assign rd_from_collector = (~collector_empty) & (~gin_fifo_full) & (~tags_fifo_full);
    assign we_to_gin_fifo = rd_from_collector;
    assign we_to_tags_fifo = we_to_gin_fifo;

    // 时钟反相DFF: ~clk触发, 延迟一拍
    flopr #(.DATA_WIDTH(1)) dff (
        .clk(~clk),
        .reset(reset),
        .d(re_from_glb),
        .q(we_to_collector)
    );

    // ---- Ifmap索引生成器 ----
    // 生成4维索引: ifmap_index(n), channel_index(q+r*q), row_index(D), col_index(W)
    ifmap_index_generator #(
        .D_WIDTH(D_WIDTH),
        .W_WIDTH(W_WIDTH),
        .n_WIDTH(n_WIDTH),
        .q_WIDTH(q_WIDTH),
        .r_WIDTH(r_WIDTH)
    ) ifmap_index_generator_inst (
        .clk(~clk),           // 反相时钟同步
        .reset(reset),

        .start(start),
        .await(collector_full),
        .busy(re_from_glb),   // busy直接作为读请求
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

    // ---- 地址映射 ----
    // 将4维索引映射为线性地址: addr = idx4*dim3*dim2*dim1 + idx3*dim2*dim1 + idx2*dim1 + idx1
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

    // ---- 内部缓冲FIFO (同宽FIFO, 仅做缓冲) ----
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

    // ---- Ifmap标签生成器 ----
    // 与数据读出同步生成路由标签
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
