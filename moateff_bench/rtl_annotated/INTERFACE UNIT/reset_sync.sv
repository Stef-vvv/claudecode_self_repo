// ============================================================================
// 模块名称: reset_sync (复位同步器)
// 在架构中的位置: INTERFACE UNIT - 跨时钟域复位信号同步
//
// 功能描述:
//   将异步复位信号同步到目标时钟域。采用移位寄存器方式：
//   在每个时钟下降沿将1'b1逐位移入sync寄存器，直到sync全1后sync_reset解除。
//
//   复位释放同步机制:
//   - reset=1 (异步复位): sync <= 1'b0, sync_reset = 1 (复位有效)
//   - reset=0 (释放复位): 每个下降沿 sync <= {sync, 1'b1}，逐步填充1
//   - 当sync所有位均为1时: sync_reset = 0 (复位解除)
//
//   此设计确保复位释放与目标时钟域同步，避免亚稳态。
//
// 时钟域说明:
//   - negedge clk触发，posedge reset异步复位
//   - 可用于任何需要同步复位的时钟域（core_clk或link_clk）
// ============================================================================

module reset_sync
(
	input wire  clk, reset,          // clk: 目标时钟域时钟，reset: 异步复位输入
	output wire sync_reset           // 同步到目标时钟域的复位信号（高有效）
);

	reg sync;                        // 移位寄存器，从0逐步填充为全1

	// ========================================================================
	// 复位释放同步逻辑:
	//   reset=1: sync清零 (sync_reset=1，复位有效)
	//   reset=0: 每个下降沿将sync左移并填入1'b1
	//   当sync全为1时sync_reset=0（复位解除）
	// ========================================================================
	always @(negedge clk, posedge reset)
	begin
		if (reset)
		begin
			sync <= 'b0;             // 异步复位: sync清零
		end

		else
		begin
			sync <= {sync,1'b1};    // 逐周期填充1（移位寄存器式同步释放）
		end
	end

	assign sync_reset = !sync;       // sync全1时复位解除，否则复位有效

endmodule
