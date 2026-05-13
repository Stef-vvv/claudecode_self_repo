// ============================================================================
// 模块名称: bias_glb (偏置全局缓冲区)
// 在架构中的位置: GLB UNIT (全局缓冲区单元) - 偏置数据存储
//
// 功能描述:
//   存储卷积层的偏置（bias）参数。采用4路Bank并行架构：
//   - 端口A (宽口): 64位宽度，用于从DRAM/接口单元批量加载偏置数据（一次写入4个16位偏置值）
//   - 端口B (窄口): 16位宽度，用于逐偏置值读出到PE阵列
//   内部由4个dual_bram实例组成，每个存储1/4地址空间的16位数据。
//
// 存储结构 (Bank划分):
//   U0_0: 存地址位[1:0]==00的偏置（wdata_a[15:0]）
//   U0_1: 存地址位[1:0]==01的偏置（wdata_a[31:16]）
//   U1_0: 存地址位[1:0]==10的偏置（wdata_a[47:32]）
//   U1_1: 存地址位[1:0]==11的偏置（wdata_a[63:48]）
//   有效存储深度 = MEM_DEPTH / 4，总数据容量 = MEM_DEPTH × 16 位
//
// 时钟域说明:
//   - negege（下降沿）clk，与dual_bram保持一致
//   - 所有4个Bank共享同一时钟
//
// 与ifmap_glb/filter_glb的差异:
//   偏置GLB的结构与ifmap_glb和filter_glb完全对称（均为4-Bank拼接），
//   仅功能用途不同：bias_glb存储偏置值而不存储特征图或权重
// ============================================================================

module bias_glb
#(
	parameter FIFO_WIDTH = 64,       // 端口A（宽口）数据宽度，默认64位 = 4×16位
	parameter DATA_WIDTH = 16,       // 端口B（窄口）数据宽度，默认16位（Q0.8定点数格式）
	parameter MEM_DEPTH = 16,        // 总存储深度，默认16（内部每个Bank深16/4=4）
	localparam ADDR_WIDTH = $clog2(MEM_DEPTH)  // 地址线位宽，自动计算（log2深度）
) (
    input wire clk,                  // 时钟信号（negedge下降沿触发）

	// ==================== 端口A (宽口，64位) ====================
	// 用于DRAM/接口单元 -> GLB的批量数据加载
	// 一次传输4个16位偏置值，分别写入4个Bank
	input wire we_a,                 // 端口A写使能（高有效）
	input wire re_a,                 // 端口A读使能（高有效）
	input wire [ADDR_WIDTH - 1:0] addr_a,   // 端口A地址（高2位选择Bank块内地址）
	input wire [FIFO_WIDTH - 1:0] wdata_a,  // 端口A写数据（64位 = 4×16位偏置值）
	output reg [FIFO_WIDTH - 1:0] rdata_a,  // 端口A读数据（64位组合输出）

	// ==================== 端口B (窄口，16位) ====================
	// 用于GLB -> PE阵列的单偏置值读出
	// 每次读取一个16位偏置值（由addr_b的低2位选择哪个Bank的数据）
	input wire we_b,                 // 端口B写使能（高有效）— 偏置GLB通常只读不写
	input wire re_b,                 // 端口B读使能（高有效）
	input wire [ADDR_WIDTH - 1:0] addr_b,   // 端口B地址（低2位选择Bank，高位选择块内地址）
	input wire [DATA_WIDTH - 1:0] wdata_b,  // 端口B写数据（16位）
	output reg [DATA_WIDTH - 1:0] rdata_b   // 端口B读数据（16位寄存器输出）
);


	// ========================================================================
	// 端口A: 读数据拼接
	// 4个Bank的16位读数据组合成64位输出：{bank11, bank10, bank01, bank00}
	// 组合逻辑，无延迟
	// ========================================================================
	wire [DATA_WIDTH - 1:0] rdata_a00, rdata_a01, rdata_a10, rdata_a11;

	always @(*) begin
        rdata_a = {rdata_a11, rdata_a10, rdata_a01, rdata_a00};
	end

	// ========================================================================
	// 端口B: 地址流水线对齐
	// addr_b经过一级flop延迟，确保addr_b_r与BRAM读数据时序对齐
	// 原因: BRAM输出在地址有效后的下一周期才稳定
	// ========================================================================
	wire [ADDR_WIDTH - 1:0] addr_b_r;
	wire [DATA_WIDTH - 1:0] rdata_b00, rdata_b01, rdata_b10, rdata_b11;

	flop #(.DATA_WIDTH(ADDR_WIDTH)) dff (
        .clk(clk),
        .d(addr_b),
        .q(addr_b_r)
    );

	// ========================================================================
	// 端口B: 读数据MUX选择
	// 根据延迟后的地址低2位 addr_b_r[1:0] 选择对应Bank的输出
	// 00 -> U0_0, 01 -> U0_1, 10 -> U1_0, 11 -> U1_1
	// ========================================================================
	always @(*) begin
		case (addr_b_r[1:0])
			2'b00: rdata_b = rdata_b00;
			2'b01: rdata_b = rdata_b01;
			2'b10: rdata_b = rdata_b10;
			2'b11: rdata_b = rdata_b11;
		endcase
	end

	// ========================================================================
	// Bank 0_0: 存储地址[1:0]==00的偏置数据
	// 端口A: 写入wdata_a[15:0]（低16位）
	// 端口B: 只有addr_b[1:0]==00时使能读写
	// ========================================================================
	dual_bram #(
		.DATA_WIDTH(DATA_WIDTH),
		.MEM_DEPTH(MEM_DEPTH / 4)
	) U0_0 (
		.clk(clk),

		// port A
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[15:0]),
		.rdata_a(rdata_a00),

		// port B
		.we_b(we_b & (~addr_b[1]) & (~addr_b[0])),
		.re_b(re_b & (~addr_b[1]) & (~addr_b[0])),
		.addr_b(addr_b[ADDR_WIDTH - 1:2]),
		.wdata_b(wdata_b),
		.rdata_b(rdata_b00)
	);

	// ========================================================================
	// Bank 0_1: 存储地址[1:0]==01的偏置数据
	// 端口A: 写入wdata_a[31:16]
	// ========================================================================
	dual_bram #(
		.DATA_WIDTH(DATA_WIDTH),
		.MEM_DEPTH(MEM_DEPTH / 4)
	) U0_1 (
		.clk(clk),

		// port A
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[31:16]),
		.rdata_a(rdata_a01),

		// port B
		.we_b(we_b & (~addr_b[1]) & (addr_b[0])),
		.re_b(re_b & (~addr_b[1]) & (addr_b[0])),
		.addr_b(addr_b[ADDR_WIDTH - 1:2]),
		.wdata_b(wdata_b),
		.rdata_b(rdata_b01)
	);

	// ========================================================================
	// Bank 1_0: 存储地址[1:0]==10的偏置数据
	// 端口A: 写入wdata_a[47:32]
	// ========================================================================
	dual_bram #(
		.DATA_WIDTH(DATA_WIDTH),
		.MEM_DEPTH(MEM_DEPTH / 4)
	) U1_0 (
		.clk(clk),

		// port A
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[47:32]),
		.rdata_a(rdata_a10),

		// port B
		.we_b(we_b & (addr_b[1]) & (~addr_b[0])),
		.re_b(re_b & (addr_b[1]) & (~addr_b[0])),
		.addr_b(addr_b[ADDR_WIDTH - 1:2]),
		.wdata_b(wdata_b),
		.rdata_b(rdata_b10)
	);

	// ========================================================================
	// Bank 1_1: 存储地址[1:0]==11的偏置数据
	// 端口A: 写入wdata_a[63:48]
	// ========================================================================
	dual_bram #(
		.DATA_WIDTH(DATA_WIDTH),
		.MEM_DEPTH(MEM_DEPTH / 4)
	) U1_1 (
		.clk(clk),

		// port A
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[63:48]),
		.rdata_a(rdata_a11),

		// port B
		.we_b(we_b & (addr_b[1]) & (addr_b[0])),
		.re_b(re_b & (addr_b[1]) & (addr_b[0])),
		.addr_b(addr_b[ADDR_WIDTH - 1:2]),
		.wdata_b(wdata_b),
		.rdata_b(rdata_b11)
	);

endmodule
