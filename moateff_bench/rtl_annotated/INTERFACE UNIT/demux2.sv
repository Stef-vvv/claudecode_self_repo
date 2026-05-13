// ============================================================================
// 模块名称: demuxxx (1选3解复用器)
// 在架构中的位置: INTERFACE UNIT - GLB子缓冲类型选择
//
// 功能描述:
//   参数化的1选3解复用器。将一路FIFO宽度输入根据2-bit select信号分配到三个GLB之一:
//   - select=00: out0 = in (rdata_to_ifmap_GLB) — 输入特征图数据
//   - select=10: out1 = in (rdata_to_filter_GLB) — 滤波器权重数据
//   - select=01: out2 = in (rdata_to_bias_GLB) — 偏置数据
//
//   注意: select=11 无匹配输出（所有输出均为0）
//
//   编码规则（来自控制器ifmap_filter和ifmap_bias信号）:
//   - ifmap_filter[1] = GLB大类选择: 0=data类(ifmap/bias), 1=weight类(filter)
//   - ifmap_bias       = data子类选择: 0=bias(GLBS), 1=ifmap(GLB)
//   编码: {ifmap_filter[1], ifmap_bias} → 00=ifmap, 10=filter, 01=bias
// ============================================================================

module demuxxx #(parameter FIFO_WIDTH = 64)  // 数据位宽（默认64位，与FIFO一致）
(
    input wire [FIFO_WIDTH-1:0] in,          // 输入数据（来自demuxx的GLB方向输出）
    input wire [1:0] select,                  // 2位选择信号（来自ifmap_filter编码）
    output wire [FIFO_WIDTH-1:0] out0,        // 输出0 -> rdata_to_ifmap_GLB (select=00)
    output wire [FIFO_WIDTH-1:0] out1,        // 输出1 -> rdata_to_filter_GLB (select=10)
	output wire [FIFO_WIDTH-1:0] out2         // 输出2 -> rdata_to_bias_GLB (select=01)
);

    // 根据2位select译码分配数据到目标GLB
    assign out0 = (select == 2'b00) ? in : 'b0;   // select=00: 数据路由到ifmap GLB
    assign out1 = (select == 2'b10) ? in : 'b0;   // select=10: 数据路由到filter GLB
	assign out2 = (select == 2'b01) ? in : 'b0;   // select=01: 数据路由到bias GLB

endmodule
