// ============================================================================
// 模块名称: muxxx (单比特2选1复用器)
// 在架构中的位置: INTERFACE UNIT - 控制/使能信号选通
//
// 功能描述:
//   单比特2选1复用器，用于选择控制/使能信号路径。
//   select1=0: out1 = in00
//   select1=1: out1 = in11
//
//   在async_fifo中用于:
//     1. 选择有效数据信号: valid = select ? r_en_GLB : valid_from_DRAM
//        (前向通路: valid来自DRAM, 反向通路: valid来自GLB)
//     2. 选择读增量信号: r_inc = select ? rinc_to_DRAM : rinc_to_GLB
//        (前向通路: 读向GLB, 反向通路: 读向DRAM)
//
// 与muxx的区别:
//   - muxxx: 单比特控制信号选择（固定1位宽）
//   - muxx:  多比特数据信号选择（FIFO_WIDTH位宽）
// ============================================================================

module muxxx
(
	input wire select1,       // 选择信号: 0=in00, 1=in11
	input wire in11,in00,     // 两个1位输入端
	output wire out1          // 选通后的1位输出
);

	assign out1 = (select1) ? in11 : in00;   // select1=1选in11, select1=0选in00

endmodule
