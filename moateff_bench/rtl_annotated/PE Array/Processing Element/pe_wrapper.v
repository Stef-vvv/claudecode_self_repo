// ============================================================================
// 模块名称: pe_wrapper (处理单元封装器 - PE with FIFOs)
// 架构位置: pe_array 内部的每个 PE 实例
//           处理单元(processing_unit) -> PE阵列(pe_array) -> pe_wrapper(本模块) -> pe(PE核心)
//           本模块为 pe.v 添加了: 时钟门控 + 输入FIFO(ifmap/filter/ipsum) + 输出FIFO(opsum)
//
// 模块功能:
//   - 时钟门控: 通过 enable 信号关闭未使用 PE 的时钟, 节省动态功耗
//   - 数据缓冲: 每个PE有4个同步FIFO (ifmap, filter, ipsum, opsum)
//   - 背压控制: 通过 almost_full/empty 标志形成自动流控
//   - 数据宽度转换: FIFO可以处理不同的读写宽度 (外部宽接口 <-> PE窄内部)
//
// 数据流:
//   外部GIN -> ifmap FIFO (宽->窄)  -> pe.v -> opsum FIFO (窄->宽) -> 外部GON
//   外部GIN -> filter FIFO (宽->窄) -> pe.v
//   外部GIN/上方PE -> ipsum FIFO (宽->窄)  -> pe.v
// ============================================================================
module pe_wrapper
#(
    // ---------- 外部接口数据宽度 (来自 GIN/GON, 可打包多像素) ----------
    parameter DATA_WIDTH_IFMAP  = 16,        // 外部ifmap数据宽度 (16-bit单像素)
    parameter DATA_WIDTH_FILTER = 64,        // 外部filter数据宽度 (64-bit=4个权重)
    parameter DATA_WIDTH_PSUM   = 64,        // 外部psum数据宽度 (64-bit=4个psp)

    // ---------- FIFO 深度参数 (条目数) ----------
    parameter IFMAP_FIFO_DEPTH  = 8,         // ifmap FIFO深度
    parameter FILTER_FIFO_DEPTH = 8,         // filter FIFO深度
    parameter PSUM_FIFO_DEPTH   = 8,         // psum FIFO深度

    // ---------- PE 内部统一数据宽度 ----------
    parameter DATA_WIDTH = 16,               // 内部数据宽度 (16-bit Q0.8)

    // ---------- 配置参数位宽 (透传给 pe.v) ----------
    parameter W_WIDTH = 8,                   // 图像宽度位宽
    parameter S_WIDTH = 5,                   // 卷积核高度位宽
    parameter F_WIDTH = 6,                   // 输入通道数位宽
    parameter U_WIDTH = 3,                   // 步幅位宽
    parameter n_WIDTH = 3,                   // ifmap加载循环位宽
    parameter p_WIDTH = 5,                   // 输出通道分片位宽
    parameter q_WIDTH = 3,                   // ifmap列分片位宽

    // ---------- SPAD 深度参数 (透传给 pe.v) ----------
    parameter IFMAP_SPAD_DEPTH  = 12,        // ifmap SPAD深度
    parameter FILTER_SPAD_DEPTH = 224,       // filter SPAD深度
    parameter PSUM_SPAD_DEPTH   = 24         // psum SPAD深度
) (
    // ---------- 时钟与复位 ----------
    input  clk,                              // 系统时钟
    input  reset,                            // 异步复位 (高有效)
    input  enable,                           // PE使能: 1=参与计算, 0=时钟关闭
    output busy,                             // PE忙碌标志 (来自 pe.v)

    // ---------- 配置参数 (透传给 pe.v) ----------
    input [W_WIDTH - 1:0] W,                 // 图像宽度
    input [S_WIDTH - 1:0] S,                 // 卷积核高度
    input [F_WIDTH - 1:0] F,                 // 输入通道数
    input [U_WIDTH - 1:0] U,                 // 步幅
    input [n_WIDTH - 1:0] n,                 // ifmap加载循环次数
    input [p_WIDTH - 1:0] p,                 // 输出通道分片数
    input [q_WIDTH - 1:0] q,                 // ifmap列分片数

    // ---------- 输入数据接口 (ifmap, 来自 GIN) ----------
    input  [DATA_WIDTH_IFMAP - 1:0] ifmap,          // ifmap 输入数据 (16-bit)
    input                           push_ifmap,     // ifmap 写使能 (GIN推送)
    output                          ifmap_fifo_full,// ifmap FIFO 满 (背压GIN)

    // ---------- 输入数据接口 (filter, 来自 GIN) ----------
    input  [DATA_WIDTH_FILTER - 1:0] filter,         // filter 输入 (64-bit, 4权重打包)
    input                            push_filter,    // filter 写使能 (GIN推送)
    output                           filter_fifo_full,// filter FIFO 满 (背压GIN)

    // ---------- 输入数据接口 (ipsum, 来自 GIN 或上方PE) ----------
    input  [DATA_WIDTH_PSUM - 1:0] ipsum,            // 输入部分和 (64-bit, 4psp打包)
    input                          push_ipsum,       // ipsum 写使能
    output                         ipsum_fifo_full,  // ipsum FIFO 满

    // ---------- 输出数据接口 (opsum, 到 GON 或下方PE) ----------
    output [DATA_WIDTH_PSUM - 1:0] opsum,            // 输出部分和 (64-bit)
    input                          pop_opsum,        // opsum 读使能 (外部拉取)
    output                         opsum_fifo_empty  // opsum FIFO 空
);

    // ---------- 门控时钟信号 ----------
    wire gated_clk;          // 门控后时钟: enable=0时停止翻转, 节省功耗

    // ========================================================================
    // clk_gating 实例: 时钟门控单元
    // 使用 latch-based 时钟门控 (AND门 + 低电平锁存器)
    // enable通过扫描链配置, 未使用的PE可完全关闭
    // ========================================================================
    clk_gating clk_gating_inst (
        .enable(enable),         // 时钟使能 (来自扫描链配置)
        .clk(clk),               // 原始时钟
        .gated_clk(gated_clk)    // 门控后时钟 -> pe.v 和 所有 FIFO
    );

    // ---------- ifmap FIFO 内部信号 ----------
    wire [DATA_WIDTH - 1:0] ifmap_from_fifo;   // FIFO读出数据 (16-bit单像素)
    wire                    pop_ifmap;          // FIFO读使能 (PE拉取,自动流控)
    wire                    ifmap_fifo_empty;   // FIFO空标志

    // ---------- filter FIFO 内部信号 ----------
    wire [DATA_WIDTH - 1:0] filter_from_fifo;   // FIFO读出数据 (16-bit单权重)
    wire                    pop_filter;         // FIFO读使能 (PE拉取,自动流控)
    wire                    filter_fifo_empty;  // FIFO空标志

    // ---------- ipsum FIFO 内部信号 ----------
    wire [DATA_WIDTH - 1:0] ipsum_from_fifo;    // FIFO读出数据 (16-bit单psp)
    wire                    pop_ipsum;          // FIFO读使能 (PE拉取)
    wire                    ipsum_fifo_empty;   // FIFO空标志

    // ---------- opsum FIFO 内部信号 ----------
    wire [DATA_WIDTH - 1:0] opsum_to_fifo;      // FIFO写入数据 (16-bit单psp)
    wire                    push_opsum;         // FIFO写使能 (PE推送)
    wire                    opsum_fifo_full;    // FIFO满标志

    // ---------- SPAD满信号 (来自 pe.v, 控制 FIFO 读取) ----------
    wire filter_spad_full;   // filter SPAD满: 停止从 filter FIFO 读
    wire ifmap_spad_full;    // ifmap SPAD满: 停止从 ifmap FIFO 读

    // ========================================================================
    // FIFO 读使能逻辑 (自动流控)
    // pop_filter: SPAD未满 AND FIFO非空 -> 从FIFO读出写入SPAD
    // pop_ifmap:  SPAD未满 AND FIFO非空 -> 从FIFO读出写入SPAD
    // 这实现了从 FIFO 到 SPAD 的自动数据搬运 (不需额外控制)
    // ========================================================================
    assign pop_filter = (~filter_spad_full) & (~filter_fifo_empty);
    assign pop_ifmap  = (~ifmap_spad_full) & (~ifmap_fifo_empty);

    // ========================================================================
    // ifmap FIFO: 输入特征图数据缓冲
    // 写端: 外部GIN推送 (DATA_WIDTH_IFMAP宽度)
    // 读端: PE内部拉取 (DATA_WIDTH宽度)
    // ========================================================================
    sync_fifo #(
        .R_DATA_WIDTH(DATA_WIDTH),           // 读端口宽度 = 16-bit
        .W_DATA_WIDTH(DATA_WIDTH_IFMAP),     // 写端口宽度 = 16-bit
        .FIFO_DEPTH(IFMAP_FIFO_DEPTH)        // 深度 = 8
    ) ifmap_fifo_inst (
        .clk(gated_clk),                     // 门控时钟
        .reset(reset),
        .write_request(push_ifmap),          // 外部写请求
        .read_request(pop_ifmap),            // 内部读请求 (自动流控)
        .wr_data(ifmap),                     // 写入数据
        .rd_data(ifmap_from_fifo),           // 读出数据 -> pe.v
        .almost_full_flag(),
        .almost_empty_flag(),
        .full_flag(ifmap_fifo_full),         // 满 -> 背压外部
        .empty_flag(ifmap_fifo_empty)        // 空 -> 停止内部读取
    );

    // ========================================================================
    // filter FIFO: 滤波器权重数据缓冲
    // 写端: 外部GIN推送 (DATA_WIDTH_FILTER=64bit, 4权重打包)
    // 读端: PE内部拉取 (DATA_WIDTH=16bit, 每次读出一个权重)
    // FIFO内部实现宽度转换 (64->16拆分)
    // ========================================================================
    sync_fifo #(
        .R_DATA_WIDTH(DATA_WIDTH),           // 读端口宽度 = 16-bit
        .W_DATA_WIDTH(DATA_WIDTH_FILTER),    // 写端口宽度 = 64-bit
        .FIFO_DEPTH(FILTER_FIFO_DEPTH)
    ) filter_fifo_inst (
        .clk(gated_clk),
        .reset(reset),
        .write_request(push_filter),
        .read_request(pop_filter),           // 自动流控
        .wr_data(filter),
        .rd_data(filter_from_fifo),          // 读出数据 -> pe.v
        .almost_full_flag(),
        .almost_empty_flag(),
        .full_flag(filter_fifo_full),
        .empty_flag(filter_fifo_empty)
    );

    // ========================================================================
    // ipsum FIFO: 输入部分和缓冲
    // 写端: 外部(上方PE或GIN)推送 (64-bit, 4psp打包)
    // 读端: PE内部拉取 (ACCUMULATE/PADDING状态)
    // almost_empty -> pe.v的ipsum_fifo_empty输入
    // ========================================================================
    sync_fifo #(
        .R_DATA_WIDTH(DATA_WIDTH),           // 读端口宽度 = 16-bit
        .W_DATA_WIDTH(DATA_WIDTH_PSUM),      // 写端口宽度 = 64-bit
        .FIFO_DEPTH(PSUM_FIFO_DEPTH)
    ) ipsum_fifo_inst (
        .clk(gated_clk),
        .reset(reset),
        .write_request(push_ipsum),
        .read_request(pop_ipsum),            // PE内部拉取
        .wr_data(ipsum),
        .rd_data(ipsum_from_fifo),           // 读出数据 -> pe.v
        .almost_full_flag(),
        .almost_empty_flag(ipsum_fifo_empty),// 几乎空 -> pe.v
        .full_flag(ipsum_fifo_full),
        .empty_flag()
    );

    // ========================================================================
    // opsum FIFO: 输出部分和缓冲
    // 写端: PE内部推送 (16-bit单psp)
    // 读端: 外部(下方PE或GON)拉取 (64-bit, 4psp打包)
    // almost_full -> pe.v的opsum_fifo_full输入
    // ========================================================================
    sync_fifo #(
        .R_DATA_WIDTH(DATA_WIDTH_PSUM),      // 读端口宽度 = 64-bit
        .W_DATA_WIDTH(DATA_WIDTH),           // 写端口宽度 = 16-bit
        .FIFO_DEPTH(PSUM_FIFO_DEPTH)
    ) opsum_fifo_inst (
        .clk(gated_clk),
        .reset(reset),
        .write_request(push_opsum),          // PE内部推送
        .read_request(pop_opsum),            // 外部拉取
        .wr_data(opsum_to_fifo),             // PE输出数据
        .rd_data(opsum),                     // 读出 -> 外部
        .almost_full_flag(opsum_fifo_full),  // 几乎满 -> pe.v
        .almost_empty_flag(),
        .full_flag(),
        .empty_flag(opsum_fifo_empty)
    );

    // ========================================================================
    // pe 实例: PE 处理核心
    // 使用门控时钟 gated_clk
    // 所有数据通过 FIFO 与外部交换
    // ========================================================================
    pe #(
        .DATA_WIDTH(DATA_WIDTH),

        .W_WIDTH(W_WIDTH),
        .S_WIDTH(S_WIDTH),
        .F_WIDTH(F_WIDTH),
        .U_WIDTH(U_WIDTH),
        .n_WIDTH(n_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),

        .IFMAP_SPAD_DEPTH(IFMAP_SPAD_DEPTH),
        .FILTER_SPAD_DEPTH(FILTER_SPAD_DEPTH),
        .PSUM_SPAD_DEPTH(PSUM_SPAD_DEPTH)
    ) pe_inst (
        .clk(gated_clk),                    // 门控时钟
        .reset(reset),
        .busy(busy),

        .W(W),
        .S(S),
        .F(F),
        .U(U),
        .n(n),
        .p(p),
        .q(q),

        // filter: FIFO -> SPAD
        .wr_filter(pop_filter),             // 写使能 (FIFO读 -> SPAD写)
        .filter_pixel(filter_from_fifo),    // 数据 (来自filter FIFO)
        .filter_spad_full(filter_spad_full),// SPAD满 -> 停止FIFO读

        // ifmap: FIFO -> SPAD
        .wr_ifmap(pop_ifmap),               // 写使能 (FIFO读 -> SPAD写)
        .ifmap_pixel(ifmap_from_fifo),      // 数据 (来自ifmap FIFO)
        .ifmap_spad_full(ifmap_spad_full),  // SPAD满 -> 停止FIFO读

        // ipsum: FIFO -> 累加器
        .pop_ipsum(pop_ipsum),              // PE拉取 ipsum
        .ipsum_pixel(ipsum_from_fifo),      // 数据 (来自ipsum FIFO)
        .ipsum_fifo_empty(ipsum_fifo_empty),// EMPTY标志

        // opsum: 加法器 -> FIFO
        .push_opsum(push_opsum),            // PE推送 opsum
        .opsum_pixel(opsum_to_fifo),        // 数据 -> opsum FIFO
        .opsum_fifo_full(opsum_fifo_full)   // FULL标志 -> 阻止PE推送
    );

endmodule
