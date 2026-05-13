// ============================================================================
// 模块名称: muxx (多比特2选1复用器)
// 在架构中的位置: INTERFACE UNIT - 数据通路选通
//
// 功能描述:
//   参数化的2选1复用器，根据1-bit select信号选择in0或in1输出。
//   select=0: out = in0
//   select=1: out = in1
//
//   在async_fifo中用于选择FIFO写入数据来源:
//   - 前向通路(select=0): wdata = wdata_from_DRAM (DRAM传入的数据)
//   - 反向通路(select=1): wdata = wdata_from_GLB (GLB回传的数据)
//
// 与muxxx的区别:
//   - muxx:  多比特数据信号选择（参数化FIFO_WIDTH位宽，默认64位）
//   - muxxx: 单比特控制信号选择（固定1位宽）
// ============================================================================

module muxx #(parameter FIFO_WIDTH = 64)   // 数据位宽（默认与FIFO宽度一致为64位）
(
	input wire select,                     // 选择信号: 0=in0, 1=in1
	input wire [FIFO_WIDTH-1:0] in1,in0,   // 两个数据输入端（同宽）
	output wire [FIFO_WIDTH-1:0] out       // 选通后的输出
);

	assign out = (select) ? in1 : in0;     // select=1选in1, select=0选in0

endmodule
