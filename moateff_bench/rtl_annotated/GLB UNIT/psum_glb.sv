// ============================================================================
// 模块名称: psum_glb (部分和全局缓冲区)
// 在架构中的位置: GLB UNIT (全局缓冲区单元) - 部分和数据存储
//
// 功能描述:
//   存储卷积计算过程中产生的部分和（partial sum, psum）数据。
//   与其他GLB（ifmap/filter/bias）的关键差异：
//   - 端口A的写使能被地址位we_a & addr_a[1:0]限定到单个Bank（非广播写入）
//     这是因为psum来自PE阵列，是逐16位数据写入的（非批量64位加载）
//   - 端口A的wdata_a位宽为DATA_WIDTH(16位)而非FIFO_WIDTH(64位)
//   - 端口A读数据rdata_a仍为64位宽（供回读到DRAM）
//
// 存储结构 (4-Bank):
//   - 4个dual_bram实例，与ifmap_glb结构对称
//   - 端口A写数据wdata_a(16位)广播到4个Bank，但只有地址匹配的Bank才使能写入
//
// 数据通路:
//   DRAM -> (64位FIFO) -> 端口A写入psum_glb(16位逐Bank写入)
//   端口B -> PE阵列(16位读出，用于累加)
//   端口A读出(64位) -> FIFO -> DRAM(回写最终结果)
//
// 时钟域说明:
//   - negege（下降沿）clk
//   - 与其他GLB模块同频同步
// ============================================================================

module psum_glb
#(
	parameter FIFO_WIDTH = 64,       // 端口A（宽口）读出数据宽度，默认64位
	parameter DATA_WIDTH = 16,       // 端口A写数据/端口B数据宽度，默认16位（Q0.8定点数）
	parameter MEM_DEPTH = 16,        // 总存储深度，默认16
	localparam ADDR_WIDTH = $clog2(MEM_DEPTH)  // 地址线位宽，自动计算
) (
    input wire clk,                  // 时钟信号（negedge下降沿触发）

	// ==================== 端口A (宽口读出/窄口写入) ====================
	// 写入: 16位部分和从PE阵列逐Bank写入
	// 读出: 64位组合输出，用于回写到DRAM
	input wire we_a,                 // 端口A写使能（高有效）
	input wire re_a,                 // 端口A读使能（高有效）
	input wire [ADDR_WIDTH - 1:0] addr_a,   // 端口A地址
	input wire [DATA_WIDTH - 1:0] wdata_a,  // 端口A写数据（16位，注意：非FIFO_WIDTH位宽）
	output reg [FIFO_WIDTH - 1:0] rdata_a,  // 端口A读数据（64位组合输出）

	// ==================== 端口B (窄口，16位) ====================
	// 用于向PE阵列输出部分和，供下一轮累加
	input wire we_b,                 // 端口B写使能（高有效）
	input wire re_b,                 // 端口B读使能（高有效）
	input wire [ADDR_WIDTH - 1:0] addr_b,   // 端口B地址
	input wire [DATA_WIDTH - 1:0] wdata_b,  // 端口B写数据
	output reg [DATA_WIDTH - 1:0] rdata_b   // 端口B读数据（16位）
);


	// ========================================================================
	// 端口A: 4个Bank读数据拼接为64位
	// 与ifmap_glb相同：{U1_1, U1_0, U0_1, U0_0}
	// ========================================================================
	wire [DATA_WIDTH - 1:0] rdata_a00, rdata_a01, rdata_a10, rdata_a11;

	always @(*) begin
        rdata_a = {rdata_a11, rdata_a10, rdata_a01, rdata_a00};
	end

	// ========================================================================
	// 端口B: 地址流水线对齐和Bank选择MUX
	// ========================================================================
	wire [ADDR_WIDTH - 1:0] addr_b_r;
	wire [DATA_WIDTH - 1:0] rdata_b00, rdata_b01, rdata_b10, rdata_b11;

	flop #(.DATA_WIDTH(ADDR_WIDTH)) dff (
        .clk(clk),
        .d(addr_b),
        .q(addr_b_r)
    );

	always @(*) begin
		case (addr_b_r[1:0])
			2'b00: rdata_b = rdata_b00;
			2'b01: rdata_b = rdata_b01;
			2'b10: rdata_b = rdata_b10;
			2'b11: rdata_b = rdata_b11;
		endcase
	end

	// ========================================================================
	// Bank实例化: 与ifmap_glb的关键差异在于端口A的写使能
	// psum_glb: we_a 需要与 addr_a[1:0] 译码相与，确保只写入目标Bank
	//           （因为psum来自PE阵列，是16位逐Bank写入）
	// 对比: ifmap_glb的we_a不限定Bank（64位广播写入所有4个Bank）
	//
	// 各Bank分配:
	//   U0_0: addr_a[1:0]==00 且 we_a 有效
	//   U0_1: addr_a[1:0]==01 且 we_a 有效
	//   U1_0: addr_a[1:0]==10 且 we_a 有效
	//   U1_1: addr_a[1:0]==11 且 we_a 有效
	// ========================================================================

	dual_bram #(
		.DATA_WIDTH(DATA_WIDTH),
		.MEM_DEPTH(MEM_DEPTH / 4)
	) U0_0 (
		.clk(clk),

		// port A: 仅当addr_a[1:0]==00时写入
		.we_a(we_a & (~addr_a[1]) & (~addr_a[0])),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a),
		.rdata_a(rdata_a00),

		// port B: addr_b[1:0]==00
		.we_b(we_b & (~addr_b[1]) & (~addr_b[0])),
		.re_b(re_b & (~addr_b[1]) & (~addr_b[0])),
		.addr_b(addr_b[ADDR_WIDTH - 1:2]),
		.wdata_b(wdata_b),
		.rdata_b(rdata_b00)
	);

	dual_bram #(
		.DATA_WIDTH(DATA_WIDTH),
		.MEM_DEPTH(MEM_DEPTH / 4)
	) U0_1 (
		.clk(clk),

		// port A: 仅当addr_a[1:0]==01时写入
		.we_a(we_a & (~addr_a[1]) & (addr_a[0])),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a),
		.rdata_a(rdata_a01),

		// port B: addr_b[1:0]==01
		.we_b(we_b & (~addr_b[1]) & (addr_b[0])),
		.re_b(re_b & (~addr_b[1]) & (addr_b[0])),
		.addr_b(addr_b[ADDR_WIDTH - 1:2]),
		.wdata_b(wdata_b),
		.rdata_b(rdata_b01)
	);

	dual_bram #(
		.DATA_WIDTH(DATA_WIDTH),
		.MEM_DEPTH(MEM_DEPTH / 4)
	) U1_0 (
		.clk(clk),

		// port A: 仅当addr_a[1:0]==10时写入
		.we_a(we_a & (addr_a[1]) & (~addr_a[0])),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a),
		.rdata_a(rdata_a10),

		// port B: addr_b[1:0]==10
		.we_b(we_b & (addr_b[1]) & (~addr_b[0])),
		.re_b(re_b & (addr_b[1]) & (~addr_b[0])),
		.addr_b(addr_b[ADDR_WIDTH - 1:2]),
		.wdata_b(wdata_b),
		.rdata_b(rdata_b10)
	);

	dual_bram #(
		.DATA_WIDTH(DATA_WIDTH),
		.MEM_DEPTH(MEM_DEPTH / 4)
	) U1_1 (
		.clk(clk),

		// port A: 仅当addr_a[1:0]==11时写入
		.we_a(we_a & (addr_a[1]) & (addr_a[0])),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a),
		.rdata_a(rdata_a11),

		// port B: addr_b[1:0]==11
		.we_b(we_b & (addr_b[1]) & (addr_b[0])),
		.re_b(re_b & (addr_b[1]) & (addr_b[0])),
		.addr_b(addr_b[ADDR_WIDTH - 1:2]),
		.wdata_b(wdata_b),
		.rdata_b(rdata_b11)
	);

endmodule
