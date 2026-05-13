// ============================================================================
// 模块名称: ifmap_glb (输入特征图全局缓冲区)
// 在架构中的位置: GLB UNIT (全局缓冲区单元) - 输入特征图数据存储
//
// 功能描述:
//   存储卷积层的输入特征图（input feature map, ifmap）数据。采用4路Bank并行架构：
//   - 端口A (宽口): 64位宽度，用于从DRAM/接口单元批量加载ifmap数据（一次写入4个16位像素值）
//   - 端口B (窄口): 16位宽度，用于逐像素读出到PE阵列进行卷积计算
//   内部由4个dual_bram实例组成，每个存储1/4地址空间的16位数据。
//
// 存储结构 (4-Bank拼接):
//   64位宽口 = 4个16位数据同时在4个Bank中并行写入（宽口批量加载，提升带宽利用率）
//   16位窄口 = 通过addr_b[1:0]选择单个Bank读出（逐像素供给PE阵列）
//   每个Bank深度 = MEM_DEPTH / 4
//
// 数据格式:
//   Q0.8定点数（16位，范围[-0.5, 0.496]）
//
// 时钟域说明:
//   - negege（下降沿）clk，与dual_bram同步
//   - addr_b经flop延迟一拍，匹配BRAM流水线读时序
//
// 与bias_glb/filter_glb的关系:
//   三者结构完全对称（均为4-Bank架构），仅数据内容用途不同
//   - ifmap_glb: 输入激活值（卷积操作数A）
//   - filter_glb: 权重值（卷积操作数B）
//   - bias_glb: 偏置值（累加后的加性项）
// ============================================================================

module ifmap_glb
#(
	parameter FIFO_WIDTH = 64,       // 端口A（宽口）数据宽度，默认64位 = 4×16位
	parameter DATA_WIDTH = 16,       // 端口B（窄口）数据宽度，默认16位（Q0.8定点数）
	parameter MEM_DEPTH = 16,        // 总存储深度，默认16
	localparam ADDR_WIDTH = $clog2(MEM_DEPTH)  // 地址线位宽，自动计算（log2深度）
) (
    input wire clk,                  // 时钟信号（negedge下降沿触发）

	// ==================== 端口A (宽口，64位) ====================
	// 用于从DRAM/接口单元批量接收ifmap数据
	// 一次传输4个16位像素值，并行写入4个Bank
	input wire we_a,                 // 端口A写使能（高有效）
	input wire re_a,                 // 端口A读使能（高有效）
	input wire [ADDR_WIDTH - 1:0] addr_a,   // 端口A地址
	input wire [FIFO_WIDTH - 1:0] wdata_a,  // 端口A写数据（64位宽）
	output reg [FIFO_WIDTH - 1:0] rdata_a,  // 端口A读数据（64位组合输出）

	// ==================== 端口B (窄口，16位) ====================
	// 用于向PE阵列逐像素输出ifmap数据
	input wire we_b,                 // 端口B写使能（高有效）
	input wire re_b,                 // 端口B读使能（高有效）
	input wire [ADDR_WIDTH - 1:0] addr_b,   // 端口B地址（低2位选择Bank）
	input wire [DATA_WIDTH - 1:0] wdata_b,  // 端口B写数据（16位）
	output reg [DATA_WIDTH - 1:0] rdata_b   // 端口B读数据（16位寄存器输出）
);


	// ========================================================================
	// 端口A: 4个Bank的16位读数据拼接为64位
	// rdata_a = {U1_1读数据, U1_0读数据, U0_1读数据, U0_0读数据}
	// ========================================================================
	wire [DATA_WIDTH - 1:0] rdata_a00, rdata_a01, rdata_a10, rdata_a11;

	always @(*) begin
        rdata_a = {rdata_a11, rdata_a10, rdata_a01, rdata_a00};
	end

	// ========================================================================
	// 端口B: 地址流水线对齐
	// addr_b经flop延迟到addr_b_r，由于BRAM读延迟为1周期，
	// 此延迟确保addr_b_r与对应的rdata_b同步到达MUX
	// ========================================================================
	wire [ADDR_WIDTH - 1:0] addr_b_r;
	wire [DATA_WIDTH - 1:0] rdata_b00, rdata_b01, rdata_b10, rdata_b11;

	flop #(.DATA_WIDTH(ADDR_WIDTH)) dff (
        .clk(clk),
        .d(addr_b),
        .q(addr_b_r)
    );

	// ========================================================================
	// 端口B: Bank选择MUX
	// 根据addr_b_r[1:0]译码选择对应Bank的读数据输出
	// 00 -> U0_0 Bank, 01 -> U0_1 Bank, 10 -> U1_0 Bank, 11 -> U1_1 Bank
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
	// Bank实例化: 4个dual_bram，每个负责存储16位宽的数据
	//
	// 端口A数据分配:
	//   U0_0 <= wdata_a[15:0]   (地址[1:0]==00)
	//   U0_1 <= wdata_a[31:16]  (地址[1:0]==01)
	//   U1_0 <= wdata_a[47:32]  (地址[1:0]==10)
	//   U1_1 <= wdata_a[63:48]  (地址[1:0]==11)
	//
	// 端口B使能条件:
	//   每个Bank只在addr_b[1:0]匹配时被使能，避免多Bank冲突
	// ========================================================================

	dual_bram #(
		.DATA_WIDTH(DATA_WIDTH),
		.MEM_DEPTH(MEM_DEPTH / 4)
	) U0_0 (
		.clk(clk),

		// port A: wdata_a[15:0]
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[15:0]),
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

		// port A: wdata_a[31:16]
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[31:16]),
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

		// port A: wdata_a[47:32]
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[47:32]),
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

		// port A: wdata_a[63:48]
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[63:48]),
		.rdata_a(rdata_a11),

		// port B: addr_b[1:0]==11
		.we_b(we_b & (addr_b[1]) & (addr_b[0])),
		.re_b(re_b & (addr_b[1]) & (addr_b[0])),
		.addr_b(addr_b[ADDR_WIDTH - 1:2]),
		.wdata_b(wdata_b),
		.rdata_b(rdata_b11)
	);

endmodule
