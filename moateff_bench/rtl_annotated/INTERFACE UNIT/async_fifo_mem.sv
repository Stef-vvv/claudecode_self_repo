// ============================================================================
// 模块名称: fifo_if_mem (FIFO存储器阵列)
// 在架构中的位置: INTERFACE UNIT - 异步FIFO存储核心
//
// 功能描述:
//   异步FIFO的存储单元，支持前向和反向两种数据通路。
//   - 前向通路(Direct_Back_Path=0): 写使能由winc && !wfull直接控制
//   - 反向通路(Direct_Back_Path=1): 写使能由w_en寄存器控制（增加了一级流水）
//
//   w_en寄存器的作用: 在反向通路中提供额外的时序宽松，
//   确保写控制在wclk域内稳定之前不会触发写入。
//
// 读操作: 组合逻辑读出（assign rdata = mem[raddr]），无需读使能
//
// 时钟域说明:
//   - wclk negege 写操作（wclk由clk_mux产生，可能为link_clk或core_clk）
//   - 组合逻辑读（无时钟），raddr由读控制模块rempty提供
// ============================================================================

module fifo_if_mem #(parameter FIFO_WIDTH = 64, DEPTH = 16, FIFO_ADDR_WIDTH = $clog2 (DEPTH))
(
    input wire 	wclk,                     // 写时钟（negedge触发，由clk_mux选通）
	input wire  reset,                    // 异步复位
	input wire 	Direct_Back_Path,         // 数据方向: 0=前向, 1=反向
	input wire 	winc,                     // 写增量使能（来自上层控制）
	input wire  wfull,                    // FIFO满标志
    input wire 	[FIFO_ADDR_WIDTH-1:0] waddr,   // 写地址（来自wfull模块）
	input wire  [FIFO_ADDR_WIDTH-1:0] raddr,   // 读地址（来自rempty模块）
    input wire 	[FIFO_WIDTH-1:0] wdata,        // 写数据
    output wire [FIFO_WIDTH-1:0] rdata         // 读数据（组合逻辑输出）
);

    // ========================================================================
    // 存储阵列: 寄存器文件实现，深度×FIFO_WIDTH
    // ========================================================================
    reg [FIFO_WIDTH-1:0] mem [DEPTH-1:0];
	reg w_en;                                   // 延迟一拍的写使能（反向通路用）

	// ========================================================================
	// w_en寄存器: 在wclk下降沿更新
	// 当winc有效且FIFO未满时，w_en置1（允许写）
	// 这个额外的寄存器级在反向通路中提供时序保护
	// ========================================================================
	always @(negedge wclk, posedge reset)
	begin
		if (reset)
			w_en <= 0;
		else
			w_en <= winc && !wfull;      // 延迟一拍的有效写使能
	end

	// ========================================================================
	// 写操作逻辑:
	// - 前向通路: 直接使用winc && !wfull控制（零延迟写入）
	// - 反向通路: 使用w_en控制（延迟一拍写入，增加时序余量）
	// ========================================================================
    always @(negedge wclk) begin
		if (!Direct_Back_Path)
		begin
			if (winc && (!wfull))        // 前向: 直接条件写入
            mem[waddr] <= wdata;
		end
		else
		begin
			if (w_en)                    // 反向: 使用延迟的w_en
            mem[waddr] <= wdata;
		end
    end

	// ========================================================================
	// 读操作: 组合逻辑直接读取（异步读）
	// 不需要读时钟，读地址由rempty模块维护
	// ========================================================================
	assign rdata = mem[raddr];

endmodule
