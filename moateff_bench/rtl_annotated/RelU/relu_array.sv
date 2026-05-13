// ============================================================================
// 模块名称: relu_array (ReLU激活函数阵列)
// 在架构中的位置: ReLU - 并行多通道ReLU计算
//
// 功能描述:
//   将NUM_INPUTS个relu单元并行实例化，对多路数据同时进行ReLU激活。
//   使用generate-for展开（genvar确保编译时展开为硬件并行结构）。
//
//   输入/输出数据布局:
//   - 拼接信号: in = {in[N-1], in[N-2], ..., in[0]}
//   - 每个in[i]宽度为DATA_WIDTH
//   - 总位宽 = NUM_INPUTS * DATA_WIDTH
//   - ith通道: in[(i+1)*DATA_WIDTH-1 : i*DATA_WIDTH]
//
//   典型应用:
//   - 对PE阵列的多通道输出同时执行ReLU激活
//   - NUM_INPUTS=4表示一次处理4个输出通道
//
// 数据格式:
//   Q0.8有符号定点数（16位, 2's补码）
// ============================================================================

module relu_array
#(
    parameter DATA_WIDTH = 16,         // 每个通道的数据位宽（默认16位Q0.8定点数）
    parameter NUM_INPUTS = 4           // 并行通道数（默认4通道）
)(
    input  [NUM_INPUTS * DATA_WIDTH-1:0] in,   // 拼接的多通道输入数据
    output [NUM_INPUTS * DATA_WIDTH-1:0] out   // 拼接的多通道ReLU输出
);

	// ========================================================================
	// 使用generate-for并行实例化NUM_INPUTS个relu单元
	// 每个relu独立处理一个通道的数据
	// ========================================================================
	genvar i;
	generate
	    for (i = 0; i < NUM_INPUTS; i = i + 1) begin : relu_gen
		relu #(.DATA_WIDTH(DATA_WIDTH)) relu_inst (
		    .in(in[(i+1) * DATA_WIDTH-1 : i * DATA_WIDTH]),     // 切片输入: 第i个通道
		    .out(out[(i+1) * DATA_WIDTH-1 : i * DATA_WIDTH])    // 切片输出: 第i个通道
		);
	    end
	endgenerate

endmodule
