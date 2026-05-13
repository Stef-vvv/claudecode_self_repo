// ============================================================================
// 模块名称: processing_unit (处理单元顶层)
// 架构位置: 系统顶层模块, 整合 PE阵列 + NoC控制器
//
// 模块功能: 处理单元是二维卷积加速器的核心计算单元
//           包含两个主要子模块:
//           1. pe_array: 12x14 PE 阵列 (负责 MAC 计算)
//           2. noc_wrapper: 片上网络控制器 (负责 GLB 内存读写和 GIN/GON 数据调度)
//
// 层次结构:
//   processing_unit(本模块)
//   +-- pe_array (12x14 PE阵列)
//   |   +-- pe_wrapper[12][14] (每个带FIFO的PE)
//   |   |   +-- clk_gating, sync_fifo x4, pe
//   |   |   |   +-- pe_controller, ifmap_spad, filter_spad, psum_spad,
//   |   |   |       multiplier, truncator, adder, zero_skipping, mux2x1, flopr
//   |   +-- gin_wrapper x3 (ifmap, filter, ipsum)
//   |   +-- gon_wrapper x1 (opsum)
//   +-- noc_wrapper (NoC: GLB <-> PE Array 数据调度)
//
// 数据流:
//   外部GLB内存 <-(NoC读写)-> NoC包装器 <-(GIN)-> PE阵列 <-(GON)-> NoC包装器 -> 外部GLB内存
//
// 配置参数说明:
//   - 卷积维度: H(图高), W(图宽), R(核高), S(核宽)
//   - 通道参数: E(输入通道), F(输出通道), U(步幅)
//   - 映射参数: m,n,e,p,q,r,t (将卷积循环映射到PE阵列的参数)
//   - ROW_MAJOR: 数据存储顺序 (1=行优先)
// ============================================================================
module processing_unit #(
    // ---------- ifmap 接口参数 ----------
    parameter DATA_WIDTH_IFMAP     = 16,  // ifmap 数据宽度
    parameter ROW_TAG_WIDTH_IFMAP  = 4,   // ifmap 行标签位宽
    parameter COL_TAG_WIDTH_IFMAP  = 5,   // ifmap 列标签位宽

    // ---------- filter 接口参数 ----------
    parameter DATA_WIDTH_FILTER    = 64,  // filter 数据宽度 (4权重打包)
    parameter ROW_TAG_WIDTH_FILTER = 4,
    parameter COL_TAG_WIDTH_FILTER = 4,

    // ---------- psum 接口参数 ----------
    parameter DATA_WIDTH_PSUM      = 64,  // psum 数据宽度 (4psp打包)
    parameter ROW_TAG_WIDTH_PSUM   = 4,
    parameter COL_TAG_WIDTH_PSUM   = 4,

    // ---------- 阵列维度 ----------
    parameter NUM_OF_ROWS = 12,           // PE行数
    parameter NUM_OF_COLS = 14,           // PE列数 (共168个PE)

    // ---------- GIN/GON FIFO 深度 ----------
    parameter GIN_FIFO_DEPTH = 16,
    parameter GON_FIFO_DEPTH = 16,

    // ---------- PE FIFO 深度 ----------
    parameter IFMAP_FIFO_DEPTH  = 4,
    parameter FILTER_FIFO_DEPTH = 8,
    parameter PSUM_FIFO_DEPTH   = 8,

    // ---------- PE SPAD 深度 ----------
    parameter IFMAP_SPAD_DEPTH  = 12,
    parameter FILTER_SPAD_DEPTH = 224,
    parameter PSUM_SPAD_DEPTH   = 24,

    // ---------- 卷积维度参数位宽 ----------
    parameter H_WIDTH = 8,               // 图像高度位宽
    parameter W_WIDTH = 8,               // 图像宽度位宽
    parameter R_WIDTH = 4,               // 卷积核高度位宽
    parameter S_WIDTH = 4,               // 卷积核宽度位宽
    parameter E_WIDTH = 6,               // 输入通道数位宽
    parameter F_WIDTH = 6,               // 输出通道数位宽
    parameter U_WIDTH = 3,               // 步幅位宽

    // ---------- NoC 映射参数位宽 ----------
    parameter m_WIDTH = 8,               // ifmap行分片位宽
    parameter n_WIDTH = 3,               // ifmap加载循环位宽
    parameter e_WIDTH = 8,               // 输入通道分片位宽
    parameter p_WIDTH = 5,               // 输出通道分片位宽
    parameter q_WIDTH = 3,               // ifmap列分片位宽
    parameter r_WIDTH = 2,               // filter行分片位宽
    parameter t_WIDTH = 3,               // filter列分片位宽

    // ---------- NoC 配置 ----------
    parameter ROW_MAJOR = 1,             // 数据存储顺序: 1=行优先
    parameter ADDR_WIDTH = 20,           // GLB内存地址位宽
    parameter DATA_WIDTH = 16            // GLB内存数据宽度
) (
    // ---------- 控制信号 ----------
    input  clk,                              // 系统时钟
    input  reset,                            // 异步复位 (高有效)
    input  start,                            // 启动信号: 开始处理
    output busy,                             // 忙碌标志: 1=正在处理
    output done,                             // 完成标志: 1=处理完成

    // ---------- 卷积维度映射参数 ----------
    // 标准卷积参数
    input [H_WIDTH - 1:0] H,                 // 图像高度
    input [W_WIDTH - 1:0] W,                 // 图像宽度
    input [R_WIDTH - 1:0] R,                 // 卷积核高度
    input [S_WIDTH - 1:0] S,                 // 卷积核宽度
    input [E_WIDTH - 1:0] E,                 // 输入通道数
    input [F_WIDTH - 1:0] F,                 // 输出通道数
    input [U_WIDTH - 1:0] U,                 // 步幅

    // 循环映射参数 (将卷积7层循环映射到PE阵列)
    input [m_WIDTH - 1:0] m,                 // ifmap行分片大小
    input [n_WIDTH - 1:0] n,                 // ifmap加载循环次数
    input [e_WIDTH - 1:0] e,                 // 输入通道分片大小
    input [p_WIDTH - 1:0] p,                 // 输出通道分片大小
    input [q_WIDTH - 1:0] q,                 // ifmap列分片大小
    input [r_WIDTH - 1:0] r,                 // filter行分片大小
    input [t_WIDTH - 1:0] t,                 // filter列分片大小

    // ---------- IFMAP GLB 接口 (NoC -> GLB) ----------
    output                    ifmap_re_from_glb,    // GLB读使能
    output [ADDR_WIDTH - 1:0] ifmap_glb_addr,       // GLB读地址
    input  [DATA_WIDTH - 1:0] ifmap_from_glb,       // GLB读出数据

    // ---------- FILTER GLB 接口 ----------
    output                    filter_re_from_glb,   // GLB读使能
    output [ADDR_WIDTH - 1:0] filter_glb_addr,      // GLB读地址
    input  [DATA_WIDTH - 1:0] filter_from_glb,      // GLB读出数据

    // ---------- PSUM GLB 接口 ----------
    output                    ipsum_re_from_glb,    // GLB读使能 (读取初始部分和)
    output [ADDR_WIDTH - 1:0] ipsum_glb_addr,       // GLB读地址
    output [ADDR_WIDTH - 1:0] bias_glb_addr,        // GLB偏置地址
    input  [DATA_WIDTH - 1:0] ipsum_from_glb,       // GLB读出数据

    // ---------- OPSUM GLB 接口 ----------
    output                    opsum_we_to_glb,      // GLB写使能 (写回最终部分和)
    output [ADDR_WIDTH - 1:0] opsum_glb_addr,       // GLB写地址
    output [DATA_WIDTH - 1:0] opsum_to_glb,         // GLB写数据

    // ---------- 扫描链 ----------
    input  logic scan_en,                           // 扫描使能
    input  logic scan_in,                           // 扫描链输入
    output logic scan_out                           // 扫描链输出
);

    // ========================================================================
    // IFMAP 内部连线 (NoC -> GIN)
    // NoC从GLB读取ifmap数据, 通过GIN分发到PE阵列
    // ========================================================================
    wire [ROW_TAG_WIDTH_IFMAP - 1:0] ifmap_row_tag;     // 目标PE行标签
    wire [COL_TAG_WIDTH_IFMAP - 1:0] ifmap_col_tag;     // 目标PE列标签
    wire push_ifmap_to_gin;                             // GIN写入使能
    wire [DATA_WIDTH_IFMAP - 1:0] ifmap_to_gin;         // ifmap数据
    wire ifmap_gin_fifo_full;                           // GIN FIFO满 (背压NoC)
    wire ifmap_tags_wr_en;                              // 标签写使能
    wire ifmap_tags_full;                               // 标签FIFO满

    // ========================================================================
    // FILTER 内部连线 (NoC -> GIN)
    // ========================================================================
    wire [ROW_TAG_WIDTH_FILTER - 1:0] filter_row_tag;
    wire [COL_TAG_WIDTH_FILTER - 1:0] filter_col_tag;
    wire push_filter_to_gin;
    wire [DATA_WIDTH_FILTER - 1:0] filter_to_gin;       // filter数据 (64-bit打包)
    wire filter_gin_fifo_full;
    wire filter_tags_wr_en;
    wire filter_tags_full;

    // ========================================================================
    // IPSUM 内部连线 (NoC -> GIN)
    // ========================================================================
    wire [ROW_TAG_WIDTH_PSUM - 1:0] ipsum_row_tag;
    wire [COL_TAG_WIDTH_PSUM - 1:0] ipsum_col_tag;
    wire push_ipsum_to_gin;
    wire [DATA_WIDTH_PSUM - 1:0] ipsum_to_gin;           // ipsum数据 (64-bit打包)
    wire ipsum_gin_fifo_full;
    wire ipsum_tags_wr_en;
    wire ipsum_tags_full;

    // ========================================================================
    // OPSUM 内部连线 (GON -> NoC)
    // ========================================================================
    wire [ROW_TAG_WIDTH_PSUM - 1:0] opsum_row_tag;
    wire [COL_TAG_WIDTH_PSUM - 1:0] opsum_col_tag;
    wire pop_opsum_from_gon;                             // GON读出使能
    wire [DATA_WIDTH_PSUM - 1:0] opsum_from_gon;        // GON读出数据
    wire opsum_gon_fifo_empty;                           // GON FIFO空
    wire opsum_tags_wr_en;
    wire opsum_tags_full;


    // ========================================================================
    // pe_array 实例: 12x14 PE 计算阵列
    // 接收来自 GIN 的 ifmap/filter/ipsum 数据
    // 执行 MAC 计算
    // 输出 opsum 到 GON
    // ========================================================================
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

        // 配置参数: 卷积维度
        .W(W), .S(S), .F(F), .U(U),
        .n(n), .p(p), .q(q),

        // ifmap GIN 连接
        .ifmap_to_gin(ifmap_to_gin),
        .push_ifmap_to_gin(push_ifmap_to_gin),
        .ifmap_gin_fifo_full(ifmap_gin_fifo_full),
        .ifmap_row_tag(ifmap_row_tag),
        .ifmap_col_tag(ifmap_col_tag),
        .ifmap_tags_wr_en(ifmap_tags_wr_en),
        .ifmap_tags_full(ifmap_tags_full),

        // filter GIN 连接
        .filter_to_gin(filter_to_gin),
        .push_filter_to_gin(push_filter_to_gin),
        .filter_gin_fifo_full(filter_gin_fifo_full),
        .filter_row_tag(filter_row_tag),
        .filter_col_tag(filter_col_tag),
        .filter_tags_wr_en(filter_tags_wr_en),
        .filter_tags_full(filter_tags_full),

        // ipsum GIN 连接
        .ipsum_to_gin(ipsum_to_gin),
        .push_ipsum_to_gin(push_ipsum_to_gin),
        .ipsum_gin_fifo_full(ipsum_gin_fifo_full),
        .ipsum_row_tag(ipsum_row_tag),
        .ipsum_col_tag(ipsum_col_tag),
        .ipsum_tags_wr_en(ipsum_tags_wr_en),
        .ipsum_tags_full(ipsum_tags_full),

        // opsum GON 连接
        .opsum_from_gon(opsum_from_gon),
        .pop_opsum_from_gon(pop_opsum_from_gon),
        .opsum_gon_fifo_empty(opsum_gon_fifo_empty),
        .opsum_row_tag(opsum_row_tag),
        .opsum_col_tag(opsum_col_tag),
        .opsum_tags_wr_en(opsum_tags_wr_en),
        .opsum_tags_full(opsum_tags_full),

        // 扫描链: 级联给 PE阵列内部的链
        .scan_en(scan_en),
        .scan_in(scan_in),
        .scan_out(scan_out)
    );

    // ========================================================================
    // noc_wrapper 实例: 片上网络控制器
    // 功能: 管理 GLB (Global Buffer) 内存的读写
    //       生成 GIN 数据分发所需的标签和数据
    //       从 GON 收集 opsum 写回 GLB
    // 实现: 嵌套循环控制器 (7层卷积循环展开)
    //       ifmap/filter/ipsum/opsum 地址生成
    //       数据打包/解包 (宽<->窄转换)
    // ========================================================================
    noc_wrapper #(
        // 卷积维度参数
        .H_WIDTH(H_WIDTH),
        .W_WIDTH(W_WIDTH),
        .R_WIDTH(R_WIDTH),
        .S_WIDTH(S_WIDTH),
        .E_WIDTH(E_WIDTH),
        .F_WIDTH(F_WIDTH),
        .U_WIDTH(U_WIDTH),

        // 循环映射参数
        .m_WIDTH(m_WIDTH),
        .n_WIDTH(n_WIDTH),
        .e_WIDTH(e_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),
        .r_WIDTH(r_WIDTH),
        .t_WIDTH(t_WIDTH),

        // 配置参数
        .ROW_MAJOR(ROW_MAJOR),
        .ADDR_WIDTH(ADDR_WIDTH),

        // FIFO 配置 (NoC与PE阵列间)
        .IFMAP_FIFO_IN_WIDTH(DATA_WIDTH_IFMAP),
        .IFMAP_FIFO_OUT_WIDTH(DATA_WIDTH_IFMAP),
        .IFMAP_FIFO_DEPTH(IFMAP_FIFO_DEPTH),

        .FILTER_FIFO_IN_WIDTH(DATA_WIDTH),
        .FILTER_FIFO_OUT_WIDTH(DATA_WIDTH_FILTER),
        .FILTER_FIFO_DEPTH(FILTER_FIFO_DEPTH),

        .PSUM_FIFO_IN_WIDTH(DATA_WIDTH),
        .PSUM_FIFO_OUT_WIDTH(DATA_WIDTH_PSUM),
        .PSUM_FIFO_DEPTH(PSUM_FIFO_DEPTH),

        // 标签位宽
        .ROW_TAG_WIDTH_IFMAP(ROW_TAG_WIDTH_IFMAP),
        .COL_TAG_WIDTH_IFMAP(COL_TAG_WIDTH_IFMAP),
        .ROW_TAG_WIDTH_FILTER(ROW_TAG_WIDTH_FILTER),
        .COL_TAG_WIDTH_FILTER(COL_TAG_WIDTH_FILTER),
        .ROW_TAG_WIDTH_PSUM(ROW_TAG_WIDTH_PSUM),
        .COL_TAG_WIDTH_PSUM(COL_TAG_WIDTH_PSUM)
    ) nocs_top_inst (
        .clk(clk),
        .reset(reset),
        .start(start),                              // 启动信号: 开始整个处理
        .busy(busy),                                // 忙碌输出
        .done(done),                                // 完成输出

        // 卷积维度参数
        .H(H), .W(W), .R(R), .S(S),
        .E(E), .F(F), .U(U),
        // 循环映射参数
        .m(m), .n(n), .e(e),
        .p(p), .q(q), .r(r), .t(t),

        // GIN/GON 状态输入 (用于流控)
        .ifmap_gin_fifo_full(ifmap_gin_fifo_full),
        .filter_gin_fifo_full(filter_gin_fifo_full),
        .ipsum_gin_fifo_full(ipsum_gin_fifo_full),
        .opsum_gon_fifo_empty(opsum_gon_fifo_empty),

        // GLB 读写使能
        .ifmap_re_from_glb(ifmap_re_from_glb),      // ifmap GLB 读
        .filter_re_from_glb(filter_re_from_glb),    // filter GLB 读
        .ipsum_re_from_glb(ipsum_re_from_glb),      // ipsum GLB 读
        .opsum_we_to_glb(opsum_we_to_glb),          // opsum GLB 写

        // GLB 地址
        .ifmap_glb_addr(ifmap_glb_addr),
        .filter_glb_addr(filter_glb_addr),
        .ipsum_glb_addr(ipsum_glb_addr),
        .bias_glb_addr(bias_glb_addr),
        .opsum_glb_addr(opsum_glb_addr),

        // GIN/GON 标签 (控制数据路由)
        .ifmap_row_tag(ifmap_row_tag),
        .ifmap_col_tag(ifmap_col_tag),
        .filter_row_tag(filter_row_tag),
        .filter_col_tag(filter_col_tag),
        .ipsum_row_tag(ipsum_row_tag),
        .ipsum_col_tag(ipsum_col_tag),
        .opsum_row_tag(opsum_row_tag),
        .opsum_col_tag(opsum_col_tag),

        // GLB 数据输入
        .ifmap_din(ifmap_from_glb),
        .filter_din(filter_from_glb),
        .ipsum_din(ipsum_from_glb),
        .opsum_din(opsum_from_gon),                  // 来自GON的opsum

        // GIN/GON FIFO 控制
        .ifmap_we_to_gin_fifo(push_ifmap_to_gin),
        .filter_we_to_gin_fifo(push_filter_to_gin),
        .ipsum_we_to_gin_fifo(push_ipsum_to_gin),
        .opsum_re_from_gon_fifo(pop_opsum_from_gon),

        // 标签 FIFO 状态
        .ifmap_tags_fifo_full(ifmap_tags_full),
        .filter_tags_fifo_full(filter_tags_full),
        .ipsum_tags_fifo_full(ipsum_tags_full),
        .opsum_tags_fifo_full(opsum_tags_full),

        // 标签写使能
        .we_ifmap_tags(ifmap_tags_wr_en),
        .we_filter_tags(filter_tags_wr_en),
        .we_ipsum_tags(ipsum_tags_wr_en),
        .we_opsum_tags(opsum_tags_wr_en),

        // GIN/GON 数据
        .ifmap_dout(ifmap_to_gin),                   // 输出到GIN
        .filter_dout(filter_to_gin),                 // 输出到GIN
        .ipsum_dout(ipsum_to_gin),                   // 输出到GIN
        .opsum_dout(opsum_to_glb)                    // 输出到GLB
    );

endmodule
