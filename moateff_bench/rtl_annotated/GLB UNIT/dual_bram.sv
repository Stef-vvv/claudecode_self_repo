// ============================================================================
// 模块名称: dual_bram (双端口块式RAM)
// 在架构中的位置: GLB UNIT (全局缓冲区单元) 的基础存储模块
//
// 功能描述:
//   参数化的双端口同步BRAM，端口A和端口B均可独立读写。
//   采用Xilinx "block" RAM风格实现（通过(* ram_style = "block" *)属性约束综合工具）。
//   本模块是ifmap_glb、filter_glb、bias_glb、psum_glb共同调用的底层存储单元。
//
// 时钟域说明:
//   - 单时钟域: 所有操作均在clk的negedge（下降沿）触发
//   - 写操作和读操作在同一negedge完成（写优先于读，即同一地址先写后读时读出旧值）
//
// 存储结构:
//   - 寄存器阵列实现，深度MEM_DEPTH，位宽DATA_WIDTH
//   - 综合时映射为FPGA的Block RAM资源
// ============================================================================

module dual_bram
#(
	parameter DATA_WIDTH = 16,        // 数据位宽，默认16位（Q0.8定点数格式）
	parameter MEM_DEPTH = 16,         // 存储器深度（地址空间大小），默认16
	localparam ADDR_WIDTH = $clog2(MEM_DEPTH)  // 地址线位宽，由深度自动计算（log2）
) (
    input wire clk,                   // 时钟信号（negedge下降沿触发）

	// ==================== 端口A ====================
	// 端口A用于大位宽数据通路（与接口单元/DRAM交互，通常为FIFO_WIDTH宽度）
	input wire we_a,                  // 端口A写使能（高有效），1=写入
	input wire re_a,                  // 端口A读使能（高有效），1=读出
	input wire [ADDR_WIDTH - 1:0] addr_a,    // 端口A地址线
	input wire [DATA_WIDTH - 1:0] wdata_a,   // 端口A写数据
	output reg [DATA_WIDTH - 1:0] rdata_a,   // 端口A读数据（寄存器输出）

	// ==================== 端口B ====================
	// 端口B用于小位宽数据通路（与PE阵列交互，通常为单一数据宽度）
    input wire we_b,                  // 端口B写使能（高有效），1=写入
	input wire re_b,                  // 端口B读使能（高有效），1=读出
	input wire [ADDR_WIDTH - 1:0] addr_b,    // 端口B地址线
	input wire [DATA_WIDTH - 1:0] wdata_b,   // 端口B写数据
	output reg [DATA_WIDTH - 1:0] rdata_b    // 端口B读数据（寄存器输出）

);

	// ========================================================================
	// 存储阵列: 使用(* ram_style = "block" *)指示综合工具映射到Block RAM
	// Block RAM是FPGA上的硬核存储资源，相比分布式RAM具有更高的密度和更低的功耗
	// ========================================================================
	(* ram_style = "block" *)
	reg [DATA_WIDTH - 1:0] mem [0:MEM_DEPTH - 1];   // 存储器阵列: 深度×位宽

	// ========================================================================
	// 端口A读写逻辑: 下降沿触发
	// 写操作: 当we_a有效时，将wdata_a写入mem[addr_a]
	// 读操作: 当re_a有效时，从mem[addr_a]读出到rdata_a
	// 注意: 同一negedge边沿内，写操作前的if先判断，读操作后的if后判断，
	//       因此同时读写同一地址时读出的是写入前的旧值（写优先）
	// ========================================================================
	always @(negedge clk) begin
		if (we_a)
			mem[addr_a] <= wdata_a;

		if (re_a)
			rdata_a <= mem[addr_a];
	end

	// ========================================================================
	// 端口B读写逻辑: 下降沿触发（与端口A行为对称）
	// 双端口可同时访问不同地址；若访问相同地址，需上层模块保证不发生写冲突
	// ========================================================================
	always @(negedge clk) begin
		if (we_b)
			mem[addr_b] <= wdata_b;

		if (re_b)
			rdata_b <= mem[addr_b];
	end

endmodule
