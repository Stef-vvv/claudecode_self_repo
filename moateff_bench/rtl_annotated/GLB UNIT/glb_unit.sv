// ============================================================================
// 模块名称: glb_unit (全局缓冲区顶层模块)
// 在架构中的位置: GLB UNIT - 顶层集成模块，连接所有GLB子模块
//
// 功能描述:
//   GLB (Global Buffer) 是Eyeriss架构中的全局缓冲层级，位于PE阵列与片外DRAM之间。
//   本模块实例化4种子GLB，用于存储不同类型的数据：
//     1. U1_IFMAP  : ifmap_glb  - 输入特征图缓冲
//     2. U2_FILTER : filter_glb - 滤波器权重缓冲
//     3. U3_BIAS   : bias_glb   - 偏置缓冲
//     4. U4_PSUM   : psum_glb   - 部分和缓冲
//
// 数据通路架构:
//   DRAM <--> Interface Unit (FIFO/跨时钟域) <--> GLB (本模块) <--> PE Array
//
//   前向通路(DRAM->PE):  DRAM -> FIFO -> port A写入GLB -> port B读出到PE阵列
//   反向通路(PE->DRAM):  PE -> port A写入psum_glb -> port A读出 -> FIFO -> DRAM
//
// 端口A vs 端口B:
//   - 端口A (宽口): 64位，用于FIFO/接口单元侧的大带宽传输
//   - 端口B (窄口): 16位，用于PE阵列侧的逐数据元素访问
//
// 时钟域说明:
//   - 单一core_clk域（negedge触发），所有子GLB同步运行
//   - glb_unit本身不处理跨时钟域，跨时钟域在interface_unit中处理
//
// 综合属性:
//   - (* keep_hierarchy = "yes" *) 保留模块层次，防止综合工具扁平化优化
// ============================================================================

(* keep_hierarchy = "yes" *)
module glb_unit
#(
    parameter FIFO_WIDTH = 64,             // 端口A（宽口）数据宽度，默认64位
    parameter DATA_WIDTH = 16,             // 端口B（窄口/PE侧）数据宽度，默认16位
	parameter IFMAP_GLB_DEPTH = 16,        // ifmap GLB存储深度，默认16
	parameter FILTER_GLB_DEPTH = 16,       // filter GLB存储深度，默认16
	parameter PSUM_GLB_DEPTH = 16,         // psum GLB存储深度，默认16
	parameter BIAS_GLB_DEPTH = 16,         // bias GLB存储深度，默认16
    localparam IFMAP_GLB_ADDR_WIDTH = $clog2(IFMAP_GLB_DEPTH),    // ifmap地址宽度（自动计算）
    localparam FILTER_GLB_ADDR_WIDTH = $clog2(FILTER_GLB_DEPTH),  // filter地址宽度
    localparam PSUM_GLB_ADDR_WIDTH = $clog2(PSUM_GLB_DEPTH),      // psum地址宽度
    localparam BIAS_GLB_ADDR_WIDTH = $clog2(BIAS_GLB_DEPTH)       // bias地址宽度
) (
	input wire clk,                        // 全局时钟（core_clk, negedge触发）

	// ========================================================================
	// IFMAP GLB 接口 (U1_IFMAP)
	// ========================================================================

	// port A: FIFO/DRAM -> ifmap_glb (64位宽口写入)
	input  wire we_a_ifmap,                // ifmap端口A写使能
	input  wire [IFMAP_GLB_ADDR_WIDTH - 1:0] addr_a_ifmap,  // ifmap端口A地址
	input  wire [FIFO_WIDTH - 1:0] wdata_a_ifmap,           // ifmap端口A写数据（64位）

	// port B: ifmap_glb -> PE阵列 (16位窄口读出)
	input  wire re_b_ifmap,                // ifmap端口B读使能
	input  wire [IFMAP_GLB_ADDR_WIDTH - 1:0] addr_b_ifmap,  // ifmap端口B地址
	output wire [DATA_WIDTH - 1:0] rdata_b_ifmap,           // ifmap端口B读数据（16位）


	// ========================================================================
	// FILTER GLB 接口 (U2_FILTER)
	// ========================================================================

	// port A: FIFO/DRAM -> filter_glb (64位宽口写入)
    input  wire we_a_filter,               // filter端口A写使能
    input  wire [FILTER_GLB_ADDR_WIDTH - 1:0] addr_a_filter, // filter端口A地址
    input  wire [FIFO_WIDTH - 1:0]  wdata_a_filter,          // filter端口A写数据（64位）

    // port B: filter_glb -> PE阵列 (16位窄口读出)
    input  wire re_b_filter,               // filter端口B读使能
    input  wire [FILTER_GLB_ADDR_WIDTH - 1:0] addr_b_filter, // filter端口B地址
    output wire [DATA_WIDTH - 1:0]  rdata_b_filter,          // filter端口B读数据（16位）


    // ========================================================================
    // BIAS GLB 接口 (U3_BIAS)
    // ========================================================================

    // port A: FIFO/DRAM -> bias_glb (64位宽口写入)
    input  wire we_a_bias,                 // bias端口A写使能
    input  wire [BIAS_GLB_ADDR_WIDTH - 1:0] addr_a_bias,     // bias端口A地址
    input  wire [FIFO_WIDTH - 1:0] wdata_a_bias,             // bias端口A写数据（64位）

    // port B: bias_glb -> PE阵列 (16位窄口读出)
    input  wire re_b_bias,                 // bias端口B读使能
    input  wire [BIAS_GLB_ADDR_WIDTH - 1:0] addr_b_bias,     // bias端口B地址
    output wire [DATA_WIDTH - 1:0] rdata_b_bias,              // bias端口B读数据（16位）


    // ========================================================================
    // PSUM GLB 接口 (U4_PSUM)
    //   注意: psum_glb 与其他GLB不同，端口A写入是16位（不是64位）
    //   且端口A需要读使能（用于回读到DRAM）
    // ========================================================================

	// port A: PE阵列 -> psum_glb (16位窄口写入) / psum_glb -> FIFO (64位宽口读出)
	input  wire we_a_psum,                 // psum端口A写使能
	input  wire re_a_psum,                 // psum端口A读使能（回读到DRAM）
	input  wire [PSUM_GLB_ADDR_WIDTH - 1:0] addr_a_psum,     // psum端口A地址
    input  wire [DATA_WIDTH - 1:0] wdata_a_psum,              // psum端口A写数据（16位，非64位）
    output wire [FIFO_WIDTH - 1:0] rdata_a_psum,              // psum端口A读数据（64位组合输出）

	// port B: psum_glb -> PE阵列 (16位窄口读出)
	input  wire re_b_psum,                 // psum端口B读使能
	input  wire [PSUM_GLB_ADDR_WIDTH - 1:0] addr_b_psum,     // psum端口B地址
	output wire [DATA_WIDTH - 1:0] rdata_b_psum               // psum端口B读数据（16位）
);

	// ========================================================================
	// U1_IFMAP: 输入特征图全局缓冲区实例化
	// 端口A: 从FIFO接收64位ifmap数据（re_a=0，只写不读）
	// 端口B: 向PE阵列输出16位ifmap数据（we_b=0，只读不写）
	// ========================================================================
	ifmap_glb #(
        .FIFO_WIDTH(FIFO_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(IFMAP_GLB_DEPTH)
    ) U1_IFMAP (
        .clk(clk),

        // port A: 仅用于接收DRAM数据（写操作）
        .we_a(we_a_ifmap),
        .re_a(1'b0),                       // 端口A不读（ifmap数据只从端口B读出）
        .addr_a(addr_a_ifmap),
        .wdata_a(wdata_a_ifmap),
        .rdata_a(),                        // 未连接（端口A不读出）

        // port B: 仅用于供给PE阵列（读操作）
        .we_b(1'b0),                       // 端口B不写
        .re_b(re_b_ifmap),
        .addr_b(addr_b_ifmap),
        .wdata_b(16'b0),
        .rdata_b(rdata_b_ifmap)
	);

	// ========================================================================
	// U2_FILTER: 滤波器权重全局缓冲区实例化
	// 与ifmap_glb使用方式相同：port A只写，port B只读
	// ========================================================================
	filter_glb #(
        .FIFO_WIDTH(FIFO_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(FILTER_GLB_DEPTH)
    ) U2_FILTER (
        .clk(clk),

        // port A: 接收DRAM权重数据（只写）
        .we_a(we_a_filter),
        .re_a(1'b0),
        .addr_a(addr_a_filter),
        .wdata_a(wdata_a_filter),
        .rdata_a(),

        // port B: 供给PE阵列权重（只读）
        .we_b(1'b0),
        .re_b(re_b_filter),
        .addr_b(addr_b_filter),
        .wdata_b(16'b0),
        .rdata_b(rdata_b_filter)
	);

    // ========================================================================
    // U3_BIAS: 偏置全局缓冲区实例化
    // 使用方式: port A只写，port B只读
    // ========================================================================
    bias_glb #(
        .FIFO_WIDTH(FIFO_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(BIAS_GLB_DEPTH)
    ) U3_BIAS (
        .clk(clk),

        // port A: 接收DRAM偏置数据（只写）
        .we_a(we_a_bias),
        .re_a(1'b0),
        .addr_a(addr_a_bias),
        .wdata_a(wdata_a_bias),
        .rdata_a(),

        // port B: 供给PE阵列偏置（只读）
        .we_b(1'b0),
        .re_b(re_b_bias),
        .addr_b(addr_b_bias),
        .wdata_b(16'b0),
        .rdata_b(rdata_b_bias)
    );

    // ========================================================================
    // U4_PSUM: 部分和全局缓冲区实例化
    // 与其他GLB的关键差异：port A既需要写入（PE->GLB, 16位逐Bank）也需要读出（GLB->DRAM, 64位拼接）
    // port B: 逐psum值输出到PE阵列用于累加
    // ========================================================================
	psum_glb #(
        .FIFO_WIDTH(FIFO_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(PSUM_GLB_DEPTH)
    ) U4_PSUM (
        .clk(clk),

        // port A: 写（PE阵列写入部分和）/ 读（回读到FIFO/DRAM）
        .we_a(we_a_psum),
        .re_a(re_a_psum),
        .addr_a(addr_a_psum),
        .wdata_a(wdata_a_psum),            // 16位部分和写入
        .rdata_a(rdata_a_psum),            // 64位组合输出到FIFO

        // port B: 只读（输出部分和到PE阵列）
        .we_b(1'b0),
        .re_b(re_b_psum),
        .addr_b(addr_b_psum),
        .wdata_b(16'b0),
        .rdata_b(rdata_b_psum)
	);

endmodule
