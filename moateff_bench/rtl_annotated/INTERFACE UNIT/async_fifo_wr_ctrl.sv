// ============================================================================
// 模块名称: wfull (FIFO写指针控制器 / 满标志生成器)
// 在架构中的位置: INTERFACE UNIT - 异步FIFO写侧控制
//
// 功能描述:
//   维护FIFO的写指针（二进制），并生成Gray码写指针和满标志。
//   采用经典的异步FIFO满标志判断：当写指针和读指针的Gray码在高位不同、次高位不同、
//   其余低位相同时，FIFO为满。
//
//   核心机制:
//   1. 二进制写指针计数器: waddrr在每次winc有效且非满时递增
//   2. 二进制转Gray码: wptr = (waddrr >> 1) ^ waddrr
//   3. 读指针同步: 两级寄存器同步来自rempty模块的rptr（Gray码）到写时钟域
//   4. 满判断: 比较wptr和sync_wq2_rptr的特定bit位
//
//   满判断条件（Gray码比较）:
//   wfull = (wptr[MSB] != rptr[MSB]) && (wptr[MSB-1] != rptr[MSB-1]) && (wptr[LSBs] == rptr[LSBs])
//   这等价于: 写指针绕了一圈追上读指针
//
// 时钟域说明:
//   - wclk negege: 写侧时钟（由clk_mux产生，可能为link_clk或core_clk）
//   - rptr → sync0 → sync1: 读指针从rclk域同步到wclk域（两级寄存器）
//   - 所有指针使用Gray码跨时钟域，每次只有1位翻转
// ============================================================================

module wfull #(parameter DEPTH = 16 , FIFO_ADDR_WIDTH = $clog2 (DEPTH))  // 深度和地址宽度
(
	input wire 	wclk,                   // 写侧时钟（negedge触发）
	input wire 	reset,                  // 异步复位
	input wire 	winc,                   // 写增量使能（每次有效脉冲，写指针+1）
	input wire 	[FIFO_ADDR_WIDTH:0] wq2_rptr,    // 来自读侧的Gray码读指针（已跨时钟域）
	output wire [FIFO_ADDR_WIDTH-1:0] waddr,     // 二进制写地址（输出给FIFO存储）
	output wire [FIFO_ADDR_WIDTH:0] wptr,         // Gray码写指针（输出给读侧判断空）
	output wire wfull                             // FIFO满标志（1=满，0=非满）
);

		// ========================================================================
		// 二进制写指针计数器
		// 在winc有效且非满时递增（防止满写）
		// ========================================================================
		reg [FIFO_ADDR_WIDTH:0] waddrr;

		always @(negedge wclk, posedge reset)
		begin
			if (reset)
				waddrr <= 'b0;          // 复位后写指针归零
			else if (winc && (!wfull))
				waddrr <= waddrr + 1;    // 写操作: 指针递增
		end

		// ========================================================================
		// 读指针跨时钟域同步链（两级寄存器）
		// wq2_rptr(Gray码) -> sync0 -> sync1 = sync_wq2_rptr
		// ========================================================================
		reg [FIFO_ADDR_WIDTH:0] sync0,sync1;
		wire [FIFO_ADDR_WIDTH:0] sync_wq2_rptr;

		always @(negedge wclk, posedge reset)
		begin
			if (reset)
			begin
				sync0 <= 0;
				sync1 <= 0;
			end

			else
			begin
				sync0 <= wq2_rptr;       // 第一级同步
				sync1 <= sync0;          // 第二级同步（稳定值）
			end
		end

		assign sync_wq2_rptr = sync1;

		// ========================================================================
		// 二进制写指针 -> Gray码写指针转换
		// Gray码: G = (B >> 1) ^ B
		// ========================================================================
		assign wptr = (waddrr >> 1) ^ waddrr;

		// ========================================================================
		// 满标志生成 (Gray码比较):
		// wfull条件:
		//   - 最高位(wptr[FIFO_ADDR_WIDTH]) != 同步读指针最高位
		//   - 次高位(wptr[FIFO_ADDR_WIDTH-1]) != 同步读指针次高位
		//   - 其余低位(wptr[FIFO_ADDR_WIDTH-2:0]) == 同步读指针低位
		// 这三条同时满足 = 写指针领先读指针一圈 = FIFO满
		// ========================================================================
		assign wfull = (wptr[FIFO_ADDR_WIDTH] != sync_wq2_rptr[FIFO_ADDR_WIDTH] && wptr[FIFO_ADDR_WIDTH-1] != sync_wq2_rptr[FIFO_ADDR_WIDTH-1] && wptr[FIFO_ADDR_WIDTH-2:0] == sync_wq2_rptr[FIFO_ADDR_WIDTH-2:0]);
		assign waddr = waddrr;           // 输出二进制写地址给存储单元

endmodule
