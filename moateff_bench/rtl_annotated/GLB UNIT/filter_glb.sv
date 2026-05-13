// ============================================================================
// 模块名称: filter_glb (滤波器权重全局缓冲区)
// 在架构中的位置: GLB UNIT (全局缓冲区单元) - 权重数据存储
//
// 功能描述:
//   存储卷积层的滤波器权重（filter weights）参数。采用4路Bank并行架构：
//   - 端口A (宽口): 64位宽度，用于从DRAM/接口单元批量加载权重数据（一次写入4个16位权重值）
//   - 端口B (窄口): 16位宽度，用于逐权重值读出到PE阵列
//   内部由4个dual_bram实例组成，每个存储1/4地址空间的16位数据。
//
// 存储结构 (Bank划分):
//   - 4个Bank按addr[1:0]地址译码分配
//   - 64位宽口被拆分为4段各16位分别写入4个Bank
//   - 窄口读取时根据addr_b[1:0] MUX选通到对应Bank
//   - 有效存储深度 = MEM_DEPTH / 4
//
// 时钟域说明:
//   - negege（下降沿）clk，所有操作同步
//   - addr_b经过flop流水线延迟一拍，匹配BRAM输出时序
//
// 与ifmap_glb/bias_glb的差异:
//   结构完全相同，仅命名区分功能用途（filter权重 vs ifmap特征图 vs bias偏置）
// ============================================================================

module filter_glb
#(
	parameter FIFO_WIDTH = 64,       // 端口A（宽口）数据宽度，默认64位 = 4×16位权重值
	parameter DATA_WIDTH = 16,       // 端口B（窄口）数据宽度，默认16位（Q0.8定点数格式）
	parameter MEM_DEPTH = 16,        // 总存储深度，默认16
	localparam ADDR_WIDTH = $clog2(MEM_DEPTH)  // 地址线位宽，由深度自动计算
) (
    input wire clk,                  // 时钟信号（negedge下降沿触发）

	// ==================== 端口A (宽口，64位) ====================
	// 用于DRAM/接口单元 -> GLB的批量权重加载
	// 一次传输4个16位权重值，分别写入4个Bank
	input wire we_a,                 // 端口A写使能（高有效）
	input wire re_a,                 // 端口A读使能（高有效）
	input wire [ADDR_WIDTH - 1:0] addr_a,   // 端口A地址
	input wire [FIFO_WIDTH - 1:0] wdata_a,  // 端口A写数据（64位）
	output reg [FIFO_WIDTH - 1:0] rdata_a,  // 端口A读数据（64位组合输出）

	// ==================== 端口B (窄口，16位) ====================
	// 用于GLB -> PE阵列的逐权重值读出
	input wire we_b,                 // 端口B写使能 — 权重GLB通常只读不写
	input wire re_b,                 // 端口B读使能（高有效）
	input wire [ADDR_WIDTH - 1:0] addr_b,   // 端口B地址（低2位选择Bank）
	input wire [DATA_WIDTH - 1:0] wdata_b,  // 端口B写数据
	output reg [DATA_WIDTH - 1:0] rdata_b   // 端口B读数据
);


	// ========================================================================
	// 端口A: 4个Bank读数据拼接为64位组合输出
	// rdata_a = {U1_1的输出, U1_0的输出, U0_1的输出, U0_0的输出}
	// ========================================================================
	wire [DATA_WIDTH - 1:0] rdata_a00, rdata_a01, rdata_a10, rdata_a11;

	always @(*) begin
        rdata_a = {rdata_a11, rdata_a10, rdata_a01, rdata_a00};
	end

	// ========================================================================
	// 端口B: 地址流水线对齐
	// addr_b_r = 上一周期的addr_b，用于匹配BRAM读延迟
	// ========================================================================
	wire [ADDR_WIDTH - 1:0] addr_b_r;
	wire [DATA_WIDTH - 1:0] rdata_b00, rdata_b01, rdata_b10, rdata_b11;

	flop #(.DATA_WIDTH(ADDR_WIDTH)) dff (
        .clk(clk),
        .d(addr_b),
        .q(addr_b_r)
    );

	// ========================================================================
	// 端口B: 输出MUX选择
	// 根据addr_b_r[1:0]选择对应Bank的16位读数据
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
	// 4个Bank实例化，每个负责存储FIFO_WIDTH/4 = 16位宽的数据
	// 端口A: 统一地址（高地址位），各自截取不同的16位段写入
	// 端口B: 按addr_b[1:0]译码选中唯一的Bank进行读写
	// ========================================================================

	dual_bram #(
		.DATA_WIDTH(DATA_WIDTH),
		.MEM_DEPTH(MEM_DEPTH / 4)
	) U0_0 (
		.clk(clk),

		// port A: wdata_a低16位 [15:0]
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[15:0]),
		.rdata_a(rdata_a00),

		// port B: addr_b[1:0]==00时选中
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

		// port A: wdata_a[31:16]
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[31:16]),
		.rdata_a(rdata_a01),

		// port B: addr_b[1:0]==01时选中
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

		// port A: wdata_a[47:32]
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[47:32]),
		.rdata_a(rdata_a10),

		// port B: addr_b[1:0]==10时选中
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

		// port A: wdata_a[63:48]
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[63:48]),
		.rdata_a(rdata_a11),

		// port B: addr_b[1:0]==11时选中
		.we_b(we_b & (addr_b[1]) & (addr_b[0])),
		.re_b(re_b & (addr_b[1]) & (addr_b[0])),
		.addr_b(addr_b[ADDR_WIDTH - 1:2]),
		.wdata_b(wdata_b),
		.rdata_b(rdata_b11)
	);

endmodule
