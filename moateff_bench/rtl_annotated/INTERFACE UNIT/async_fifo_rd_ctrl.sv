// ============================================================================
// 模块名称: rempty (FIFO读指针控制器 / 空标志生成器)
// 在架构中的位置: INTERFACE UNIT - 异步FIFO读侧控制
//
// 功能描述:
//   维护FIFO的读指针（二进制），并生成Gray码读指针和空标志。
//   采用经典的异步FIFO空标志判断：当读指针的Gray码等于同步后的写指针Gray码时，FIFO为空。
//
//   核心机制:
//   1. 二进制读指针计数器: raddrr在每次rinc有效且非空时递增
//   2. 二进制转Gray码: rptr = (raddrr >> 1) ^ raddrr
//   3. 写指针同步: 两级寄存器同步来自wfull模块的wptr（Gray码）到读时钟域
//   4. 空判断: rempty = (rptr == sync_rq2_wptr) — Gray码完全相等
//
// 时钟域说明:
//   - rclk negege: 读侧时钟（由clk_mux产生，可能为link_clk或core_clk）
//   - wptr → sync0 → sync1: 写指针从wclk域同步到rclk域（两级寄存器）
//   - 所有指针使用Gray码跨时钟域，每次只有1位翻转，避免亚稳态采样错误
// ============================================================================

module rempty #(parameter DEPTH = 16, FIFO_ADDR_WIDTH = $clog2(DEPTH))  // 深度和地址宽度
(
	input wire 	rclk,reset,             // 读侧时钟（negedge触发），异步复位
	input wire 	rinc,                   // 读增量使能（每次有效脉冲，读指针+1）
	input wire 	[FIFO_ADDR_WIDTH:0] rq2_wptr,   // 来自写侧的Gray码写指针（已跨时钟域）
	output wire [FIFO_ADDR_WIDTH-1:0] raddr,    // 二进制读地址（输出给FIFO存储）
	output wire [FIFO_ADDR_WIDTH:0] rptr,        // Gray码读指针（输出给写侧判断满）
	output wire rempty                           // FIFO空标志（1=空，0=非空）
);

		// ========================================================================
		// 二进制读指针计数器
		// 在rinc有效且非空时递增（防止空读）
		// ========================================================================
		reg [FIFO_ADDR_WIDTH:0] raddrr;

		always @(negedge rclk, posedge reset)
		begin
			if (reset)
				raddrr <= 'b0;          // 复位后读指针归零

			else if (rinc && !rempty)
				raddrr <= raddrr + 1;    // 读操作: 指针递增
		end

		// ========================================================================
		// 写指针跨时钟域同步链（两级寄存器）
		// rq2_wptr(Gray码) -> sync0 -> sync1 = sync_rq2_wptr
		// 两级同步消除亚稳态
		// ========================================================================
		reg [FIFO_ADDR_WIDTH:0] sync0,sync1;
		wire [FIFO_ADDR_WIDTH:0] sync_rq2_wptr;

		always @(negedge rclk, posedge reset)
		begin
			if (reset)
			begin
				sync0 <= 0;
				sync1 <= 0;
			end

			else
			begin
				sync0 <= rq2_wptr;       // 第一级同步
				sync1 <= sync0;          // 第二级同步（稳定值）
			end
		end

		assign sync_rq2_wptr = sync1;    // 同步后的写指针Gray码

		// ========================================================================
		// 二进制读指针 -> Gray码读指针转换
		// Gray码: G[n] = B[n] ^ B[n+1] (或等价的 G = (B >> 1) ^ B)
		// Gray码特性: 相邻值只差1位，适合跨时钟域传输
		// ========================================================================
		assign rptr = (raddrr >> 1) ^ raddrr;

		// ========================================================================
		// 空标志生成:
		// 当读指针Gray码 == 写指针Gray码时，FIFO为空
		// 注意: 两个指针都在rclk域比较（wptr已通过同步链同步）
		// ========================================================================
		assign rempty = (rptr == sync_rq2_wptr);
		assign raddr = raddrr;           // 输出二进制读地址给存储单元

endmodule
