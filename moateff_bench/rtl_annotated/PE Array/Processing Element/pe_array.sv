// ============================================================================
// 模块名称: pe_array (PE 阵列 - 12行 x 14列)
// 架构位置: 处理单元内部的 PE 阵列顶层
//           处理单元(processing_unit) -> pe_array(本模块) -> 12x14 pe_wrapper -> pe
//
// 模块功能: 管理和连接 12x14=168 个 PE 的二维阵列
//           - 实例化 generate for 循环创建 PE 矩阵
//           - 集成 GIN (Global Input Network) 用于 ifmap/filter/ipsum 数据分发
//           - 集成 GON (Global Output Network) 用于 opsum 数据收集
//           - 扫描链 (scan chain) 配置每个PE的 enable/ipsum_sel/opsum_sel
//           - PE 间部分和传递 (上->下: opsum[i+1] -> ipsum[i])
//
// PE 间数据流:
//   ifmap:  GIN -> 各PE的ifmap FIFO (行列标签路由分发)
//   filter:  GIN -> 各PE的filter FIFO (行列标签路由分发)
//   ipsum:   GIN -> 第一行PE, 或 opsum[i+1] -> ipsum[i] (行间数据流)
//   opsum:   PE[i] -> opsum FIFO -> PE[i-1] ipsum, 或 GON收集
//
// 扫描链结构 (6条链级联):
//   scan_in -> enable[0..ROWS] -> ipsum_ln_sel[0..ROWS] -> opsum_ln_sel[0..ROWS]
//          -> GIN_ifmap -> GIN_filter -> GIN_ipsum -> GON_opsum -> scan_out
// ============================================================================
module pe_array #(
    // ---------- ifmap 接口参数 ----------
    parameter DATA_WIDTH_IFMAP     = 16,  // ifmap 数据宽度 (单像素)
    parameter ROW_TAG_WIDTH_IFMAP  = 4,   // ifmap 行标签位宽
    parameter COL_TAG_WIDTH_IFMAP  = 5,   // ifmap 列标签位宽

    // ---------- filter 接口参数 ----------
    parameter DATA_WIDTH_FILTER    = 64,  // filter 数据宽度 (4权重打包)
    parameter ROW_TAG_WIDTH_FILTER = 4,   // filter 行标签位宽
    parameter COL_TAG_WIDTH_FILTER = 4,   // filter 列标签位宽

    // ---------- psum 接口参数 ----------
    parameter DATA_WIDTH_PSUM      = 64,  // psum 数据宽度 (4psp打包)
    parameter ROW_TAG_WIDTH_PSUM   = 4,   // psum 行标签位宽
    parameter COL_TAG_WIDTH_PSUM   = 4,   // psum 列标签位宽

    // ---------- 阵列维度 ----------
    parameter NUM_OF_ROWS = 12,           // PE 行数
    parameter NUM_OF_COLS = 14,           // PE 列数

    // ---------- GIN/GON FIFO 深度 ----------
    parameter GIN_FIFO_DEPTH = 16,        // GIN 数据FIFO深度
    parameter GON_FIFO_DEPTH = 16,        // GON 数据FIFO深度

    // ---------- PE 内部参数 ----------
    parameter DATA_WIDTH = 16,            // PE内部数据宽度 (16-bit Q0.8)

    parameter PE_IFMAP_FIFO_DEPTH  = 4,   // PE的ifmap FIFO深度
    parameter PE_FILTER_FIFO_DEPTH = 8,   // PE的filter FIFO深度
    parameter PE_PSUM_FIFO_DEPTH   = 8,   // PE的psum FIFO深度

    // ---------- 配置参数位宽 ----------
    parameter W_WIDTH = 8,                // 图像宽度位宽
    parameter S_WIDTH = 5,                // 卷积核高度位宽
    parameter F_WIDTH = 6,                // 输入通道数位宽
    parameter U_WIDTH = 3,                // 步幅位宽
    parameter n_WIDTH = 3,                // ifmap加载循环位宽
    parameter p_WIDTH = 5,                // 输出通道分片位宽
    parameter q_WIDTH = 3,                // ifmap列分片位宽

    // ---------- SPAD 深度 ----------
    parameter IFMAP_SPAD_DEPTH  = 12,     // ifmap SPAD深度
    parameter FILTER_SPAD_DEPTH = 224,    // filter SPAD深度
    parameter PSUM_SPAD_DEPTH   = 24      // psum SPAD深度
)(
    // ---------- 控制信号 ----------
    input logic clk,                             // 系统时钟
    input logic reset,                           // 异步复位

    // ---------- PE 控制 ----------
    // 二维busy信号: 每个PE的忙碌状态 [行][列]
    output logic busy [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS - 1],

    // ---------- 配置参数 ----------
    input logic [W_WIDTH - 1:0] W,               // 图像宽度
    input logic [S_WIDTH - 1:0] S,               // 卷积核高度
    input logic [F_WIDTH - 1:0] F,               // 输入通道数
    input logic [U_WIDTH - 1:0] U,               // 步幅
    input logic [n_WIDTH - 1:0] n,               // ifmap加载循环次数
    input logic [p_WIDTH - 1:0] p,               // 输出通道分片数
    input logic [q_WIDTH - 1:0] q,               // ifmap列分片数

    // ---------- IFMAP 接口 (GIN输入) ----------
    input  logic [DATA_WIDTH_IFMAP - 1:0] ifmap_to_gin,    // ifmap数据 -> GIN
    input  logic                          push_ifmap_to_gin,// GIN写使能
    output logic                          ifmap_gin_fifo_full,// GIN FIFO满
    // ifmap 标签路由
    input  logic [ROW_TAG_WIDTH_IFMAP - 1:0] ifmap_row_tag,    // 目标行标签
    input  logic [COL_TAG_WIDTH_IFMAP - 1:0] ifmap_col_tag,    // 目标列标签
    input  logic                             ifmap_tags_wr_en, // 标签写使能
    output logic                             ifmap_tags_full,  // 标签FIFO满

    // ---------- FILTER 接口 (GIN输入) ----------
    input  logic [DATA_WIDTH_FILTER - 1:0] filter_to_gin,    // filter数据 -> GIN
    input  logic                           push_filter_to_gin,// GIN写使能
    output logic                           filter_gin_fifo_full,// GIN FIFO满
    // filter 标签路由
    input  logic [ROW_TAG_WIDTH_FILTER - 1:0] filter_row_tag,
    input  logic [COL_TAG_WIDTH_FILTER - 1:0] filter_col_tag,
    input  logic                              filter_tags_wr_en,
    output logic                              filter_tags_full,

    // ---------- IPSUM 接口 (GIN输入) ----------
    input  logic [DATA_WIDTH_PSUM - 1:0] ipsum_to_gin,      // ipsum数据 -> GIN
    input  logic                         push_ipsum_to_gin,  // GIN写使能
    output logic                         ipsum_gin_fifo_full, // GIN FIFO满
    // ipsum 标签路由
    input  logic [ROW_TAG_WIDTH_PSUM - 1:0] ipsum_row_tag,
    input  logic [COL_TAG_WIDTH_PSUM - 1:0] ipsum_col_tag,
    input  logic                            ipsum_tags_wr_en,
    output logic                            ipsum_tags_full,

    // ---------- OPSUM 接口 (GON输出) ----------
    output logic [DATA_WIDTH_PSUM - 1:0] opsum_from_gon,     // GON输出数据
    input  logic                         pop_opsum_from_gon, // 外部读使能
    output logic                         opsum_gon_fifo_empty,// GON FIFO空
    // opsum 标签 (外部写入标签以选择从哪个PE读取)
    input  logic [ROW_TAG_WIDTH_PSUM - 1:0] opsum_row_tag,
    input  logic [COL_TAG_WIDTH_PSUM - 1:0] opsum_col_tag,
    input  logic                            opsum_tags_wr_en,
    output logic                            opsum_tags_full,

    // ---------- 扫描链 ----------
    input  logic scan_en,                            // 扫描使能
    input  logic scan_in,                            // 扫描链输入
    output logic scan_out                            // 扫描链输出
);

    // ========================================================================
    // GIN -> PE 数据分发信号 (二维展开)
    // 每个PE有自己的数据总线, GIN根据标签路由将数据送到对应PE
    // ========================================================================

    // ifmap 分发: GIN -> 各PE
    logic [DATA_WIDTH_IFMAP - 1:0] ifmap_from_gin [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS - 1];
    logic [0:NUM_OF_COLS - 1] push_ifmap_to_pe    [0:NUM_OF_ROWS - 1];  // PE写使能
    logic [0:NUM_OF_COLS - 1] ifmap_pe_fifo_full  [0:NUM_OF_ROWS - 1];  // PE FIFO满
    logic [0:NUM_OF_COLS - 1] ifmap_gin_ready     [0:NUM_OF_ROWS - 1];  // PE就绪 (GIN可发)

    // filter 分发: GIN -> 各PE
    logic [DATA_WIDTH_FILTER - 1:0] filter_from_gin [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS - 1];
    logic [0:NUM_OF_COLS - 1] push_filter_to_pe     [0:NUM_OF_ROWS - 1];
    logic [0:NUM_OF_COLS - 1] filter_pe_fifo_full   [0:NUM_OF_ROWS - 1];
    logic [0:NUM_OF_COLS - 1] filter_gin_ready      [0:NUM_OF_ROWS - 1];

    // ipsum 分发: GIN -> 各PE
    logic [DATA_WIDTH_PSUM - 1:0] ipsum_from_gin        [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS-1];
    logic [0:NUM_OF_COLS - 1] push_ipsum_to_pe_from_gin [0:NUM_OF_ROWS - 1];
    logic [0:NUM_OF_COLS - 1] ipsum_pe_fifo_full        [0:NUM_OF_ROWS - 1];
    logic [0:NUM_OF_COLS - 1] ipsum_gin_ready           [0:NUM_OF_ROWS - 1];

    // opsum 收集: 各PE -> GON
    logic [DATA_WIDTH_PSUM - 1:0] opsum_from_pe        [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS-1];
    logic [0:NUM_OF_COLS - 1] pop_opsum_from_pe_to_gon [0:NUM_OF_ROWS - 1];
    logic [0:NUM_OF_COLS - 1] opsum_pe_fifo_empty      [0:NUM_OF_ROWS - 1];
    logic [0:NUM_OF_COLS - 1] opsum_gon_ready          [0:NUM_OF_ROWS - 1];

    // ---------- 扫描链级联信号 ----------
    // 6条扫描链级联: enable -> ipsum_ln_sel -> opsum_ln_sel -> GIN_ifmap -> GIN_filter -> GIN_ipsum -> GON
    logic [0:5] scan_w;                              // 扫描链段间连接 [0..5]
    logic scan_w_enable [0:NUM_OF_ROWS];             // enable链: 行间级联
    logic scan_w_ipsum_ln_sel [0:NUM_OF_ROWS];       // ipsum选择链: 行间级联
    logic scan_w_opsum_ln_sel [0:NUM_OF_ROWS];       // opsum选择链: 行间级联

    // PE配置信号 (由扫描链加载)
    logic [0:NUM_OF_COLS - 1] enable [0:NUM_OF_ROWS - 1];       // PE使能 [行][列]
    logic [0:NUM_OF_COLS - 1] ipsum_ln_sel [0:NUM_OF_ROWS - 1]; // ipsum源选择: 1=GIN, 0=上方PE
    logic [0:NUM_OF_COLS - 1] opsum_ln_sel [0:NUM_OF_ROWS - 1]; // opsum目标: 1=GON, 0=下方PE

    // ========================================================================
    // 扫描链入口连接
    // 6条链的顺序:
    //   scan_w[0] = enable链输出     (-> scan_w_enable[0]=scan_in)
    //   scan_w[1] = ipsum_sel链输出   (-> scan_w_ipsum_ln_sel[0])
    //   scan_w[2] = opsum_sel链输出   (-> scan_w_opsum_ln_sel[0])
    //   scan_w[3] = GIN_ifmap输出     (-> ifmap_gin)
    //   scan_w[4] = GIN_filter输出    (-> filter_gin)
    //   scan_w[5] = GIN_ipsum输出     (-> ipsum_gin)
    //   scan_out  = GON 输出          (-> opsum_gon)
    // ========================================================================
    assign scan_w_enable[0]= scan_in;              // 第一条链入口 = scan_in
    assign scan_w[0] = scan_w_enable[NUM_OF_ROWS]; // enable链出口 -> scan_w[0]
    assign scan_w_ipsum_ln_sel[0]= scan_w[0];      // 第二条链入口
    assign scan_w[1] = scan_w_ipsum_ln_sel[NUM_OF_ROWS]; // ipsum链出口
    assign scan_w_opsum_ln_sel[0]= scan_w[1];      // 第三条链入口
    assign scan_w[2] = scan_w_opsum_ln_sel[NUM_OF_ROWS]; // opsum链出口

    // ========================================================================
    // PE 阵列生成 (generate for: 12行 x 14列)
    // 每行有3个扫描链FF (enable, ipsum_sel, opsum_sel)
    // 每个位置实例化一个 pe_wrapper
    //
    // PE间psum连接:
    //   ipsum_ln_sel[i][j] = 1: PE[i][j]的ipsum来自GIN (第一行或独立模式)
    //   ipsum_ln_sel[i][j] = 0: PE[i][j]的ipsum来自PE[i+1][j]的opsum (行间级联)
    //   opsum_ln_sel[i][j] = 1: PE[i][j]的opsum输出到GON (最后一行或独立模式)
    //   opsum_ln_sel[i][j] = 0: PE[i][j]的opsum传递到PE[i-1][j]的ipsum
    // ========================================================================
    genvar i, j;
    generate
        for (i = 0; i < NUM_OF_ROWS; i = i + 1) begin : row
            // PE使能扫描链: 每行一个N位FF (N=NUM_OF_COLS)
            scan_ff_Nbit #(.DATA_WIDTH(NUM_OF_COLS)) pe_array_enable_ff (
                .clk(clk),
                .reset(reset),
                .scan_en(scan_en),
                .scan_in(scan_w_enable[i]),
                .q(enable[i]),                      // 输出到该行所有PE
                .scan_out(scan_w_enable[i+1])        // 级联到下一行
            );

            // ipsum源选择扫描链: 每行一个N位FF
            scan_ff_Nbit #(.DATA_WIDTH(NUM_OF_COLS)) ipsum_ln_ff (
                .clk(clk),
                .reset(reset),
                .scan_en(scan_en),
                .scan_in(scan_w_ipsum_ln_sel[i]),
                .q(ipsum_ln_sel[i]),
                .scan_out(scan_w_ipsum_ln_sel[i+1])
            );

            // opsum目标选择扫描链: 每行一个N位FF
            scan_ff_Nbit #(.DATA_WIDTH(NUM_OF_COLS)) opsum_ln_ff (
                .clk(clk),
                .reset(reset),
                .scan_en(scan_en),
                .scan_in(scan_w_opsum_ln_sel[i]),
                .q(opsum_ln_sel[i]),
                .scan_out(scan_w_opsum_ln_sel[i+1])
            );

            for (j = 0; j < NUM_OF_COLS; j = j + 1) begin : col
                // ============================================================
                // pe_wrapper 实例: 每个位置一个PE
                // ============================================================
                pe_wrapper #(
                    .DATA_WIDTH(DATA_WIDTH),

                    .DATA_WIDTH_IFMAP(DATA_WIDTH_IFMAP),
                    .DATA_WIDTH_FILTER(DATA_WIDTH_FILTER),
                    .DATA_WIDTH_PSUM(DATA_WIDTH_PSUM),

                    .IFMAP_FIFO_DEPTH(PE_IFMAP_FIFO_DEPTH),
                    .FILTER_FIFO_DEPTH(PE_FILTER_FIFO_DEPTH),
                    .PSUM_FIFO_DEPTH(PE_PSUM_FIFO_DEPTH),

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
                    ) PE_inst (
                    .clk(clk),
                    .reset(reset),
                    .busy(busy[i][j]),
                    .enable(enable[i][j]),           // 来自扫描链的PE使能

                    // 配置参数
                    .W(W), .S(S), .F(F), .U(U),
                    .n(n), .p(p), .q(q),

                    // ifmap: 来自 GIN
                    .push_ifmap(push_ifmap_to_pe[i][j]),
                    .ifmap(ifmap_from_gin[i][j]),
                    .ifmap_fifo_full(ifmap_pe_fifo_full[i][j]),

                    // filter: 来自 GIN
                    .push_filter(push_filter_to_pe[i][j]),
                    .filter(filter_from_gin[i][j]),
                    .filter_fifo_full(filter_pe_fifo_full[i][j]),

                    // ipsum: 来自GIN(ipsum_sel=1) 或 上方PE[i+1]的opsum(ipsum_sel=0)
                    .push_ipsum(ipsum_ln_sel[i][j] ? push_ipsum_to_pe_from_gin[i][j] : ((~opsum_pe_fifo_empty[i+1][j]) & (~ipsum_pe_fifo_full[i][j]))),
                    .ipsum(ipsum_ln_sel[i][j] ? ipsum_from_gin[i][j] : opsum_from_pe[i+1][j]),
                    .ipsum_fifo_full(ipsum_pe_fifo_full[i][j]),

                    // opsum: 到GON(opsum_sel=1) 或 到下方PE[i-1]的ipsum(opsum_sel=0)
                    .pop_opsum(opsum_ln_sel[i][j] ? pop_opsum_from_pe_to_gon[i][j] : ((~opsum_pe_fifo_empty[i][j]) & (~ipsum_pe_fifo_full[i-1][j]))),
                    .opsum(opsum_from_pe[i][j]),
                    .opsum_fifo_empty(opsum_pe_fifo_empty[i][j])
                );

                // GIN/GON 就绪信号: FIFO未满=就绪可接收, FIFO非空=就绪可发送
                assign ifmap_gin_ready [i][j] = ~ifmap_pe_fifo_full [i][j];
                assign filter_gin_ready[i][j] = ~filter_pe_fifo_full[i][j];
                assign ipsum_gin_ready [i][j] = ~ipsum_pe_fifo_full [i][j];
                assign opsum_gon_ready [i][j] = ~opsum_pe_fifo_empty[i][j];
            end
        end
    endgenerate

    // ========================================================================
    // IFMAP GIN 实例: 全局输入网络 (ifmap数据分发)
    // 接收外部ifmap数据和行列标签, 通过标签匹配将数据路由到目标PE
    // 数据宽度: DATA_WIDTH_IFMAP (16-bit)
    // ========================================================================
    gin_wrapper #(
        .DATA_WIDTH(DATA_WIDTH_IFMAP),
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH_IFMAP),
        .COL_TAG_WIDTH(COL_TAG_WIDTH_IFMAP),
        .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS),
        .GIN_DATA_FIFO_DEPTH(GIN_FIFO_DEPTH),
        .GIN_TAGS_FIFO_DEPTH(GIN_FIFO_DEPTH)
    ) ifmap_gin_inst (
        .clk(clk),
        .reset(reset),
        .row_tag(ifmap_row_tag),
        .col_tag(ifmap_col_tag),
        .ready_in(ifmap_gin_ready),          // 各PE就绪信号
        .data_in(ifmap_to_gin),              // 输入数据
        .data_out(ifmap_from_gin),           // 分发到各PE
        .enable_out(push_ifmap_to_pe),       // 各PE写使能
        .tags_wr_en(ifmap_tags_wr_en),
        .tags_full(ifmap_tags_full),
        .data_wr_en(push_ifmap_to_gin),
        .data_full(ifmap_gin_fifo_full),
        .scan_en_id(scan_en),
        .scan_in_id(scan_w[2]),              // 扫描链接口
        .scan_out_id(scan_w[3])
    );

    // ========================================================================
    // FILTER GIN 实例: 全局输入网络 (filter权重分发)
    // 数据宽度: DATA_WIDTH_FILTER (64-bit, 4权重打包)
    // ========================================================================
    gin_wrapper #(
        .DATA_WIDTH(DATA_WIDTH_FILTER),
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH_FILTER),
        .COL_TAG_WIDTH(COL_TAG_WIDTH_FILTER),
        .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS),
        .GIN_DATA_FIFO_DEPTH(GIN_FIFO_DEPTH),
        .GIN_TAGS_FIFO_DEPTH(GIN_FIFO_DEPTH)
    ) filter_gin_inst (
        .clk(clk),
        .reset(reset),
        .row_tag(filter_row_tag),
        .col_tag(filter_col_tag),
        .ready_in(filter_gin_ready),
        .data_in(filter_to_gin),
        .data_out(filter_from_gin),
        .enable_out(push_filter_to_pe),
        .tags_wr_en(filter_tags_wr_en),
        .tags_full(filter_tags_full),
        .data_wr_en(push_filter_to_gin),
        .data_full(filter_gin_fifo_full),
        .scan_en_id(scan_en),
        .scan_in_id(scan_w[3]),
        .scan_out_id(scan_w[4])
    );

    // ========================================================================
    // IPSUM GIN 实例: 全局输入网络 (部分和输入分发)
    // 数据宽度: DATA_WIDTH_PSUM (64-bit, 4psp打包)
    // ========================================================================
    gin_wrapper #(
        .DATA_WIDTH(DATA_WIDTH_PSUM),
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH_PSUM),
        .COL_TAG_WIDTH(COL_TAG_WIDTH_PSUM),
        .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS),
        .GIN_DATA_FIFO_DEPTH(GIN_FIFO_DEPTH),
        .GIN_TAGS_FIFO_DEPTH(GIN_FIFO_DEPTH)
    ) ipsum_gin_inst (
        .clk(clk),
        .reset(reset),
        .row_tag(ipsum_row_tag),
        .col_tag(ipsum_col_tag),
        .ready_in(ipsum_gin_ready),
        .data_in(ipsum_to_gin),
        .data_out(ipsum_from_gin),
        .enable_out(push_ipsum_to_pe_from_gin),
        .tags_wr_en(ipsum_tags_wr_en),
        .tags_full(ipsum_tags_full),
        .data_wr_en(push_ipsum_to_gin),
        .data_full(ipsum_gin_fifo_full),
        .scan_en_id(scan_en),
        .scan_in_id(scan_w[4]),
        .scan_out_id(scan_w[5])
    );

    // ========================================================================
    // OPSUM GON 实例: 全局输出网络 (部分和收集输出)
    // 接收各PE的输出部分和, 根据外部标签选择读取
    // 数据宽度: DATA_WIDTH_PSUM (64-bit)
    // ========================================================================
    gon_wrapper #(
        .DATA_WIDTH(DATA_WIDTH_PSUM),
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH_PSUM),
        .COL_TAG_WIDTH(COL_TAG_WIDTH_PSUM),
        .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS),
        .GON_DATA_FIFO_DEPTH(GIN_FIFO_DEPTH),
        .GON_TAGS_FIFO_DEPTH(GON_FIFO_DEPTH)
    ) opsum_gon_inst (
        .clk(clk),
        .reset(reset),
        .row_tag(opsum_row_tag),
        .col_tag(opsum_col_tag),
        .ready_in(opsum_gon_ready),
        .data_in(opsum_from_pe),             // 各PE的opsum数据
        .data_out(opsum_from_gon),           // 输出到外部
        .enable_out(pop_opsum_from_pe_to_gon),// 各PE的读使能
        .tags_wr_en(opsum_tags_wr_en),
        .tags_full(opsum_tags_full),
        .data_rd_en(pop_opsum_from_gon),
        .data_empty(opsum_gon_fifo_empty),
        .scan_en_id(scan_en),
        .scan_in_id(scan_w[5]),
        .scan_out_id(scan_out)               // 最终扫描链输出
    );

endmodule
