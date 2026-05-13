// ============================================================================
// 模块名称: demuxx (1选2解复用器)
// 在架构中的位置: INTERFACE UNIT - 数据通路分配（FIFO读数据路由）
//
// 功能描述:
//   参数化的1选2解复用器。将一路FIFO宽度输入根据select信号分配到两个输出之一:
//   - select=0: out0 = in, out1 = 0 (数据发往GLB)
//   - select=1: out1 = in, out0 = 0 (数据发往DRAM)
//
//   在async_fifo中用于根据Direct_Back_Path选择FIFO读出数据的去向:
//   - 前向通路(Direct_Back_Path=0, select=0): FIFO数据 -> rdata_to_GLB
//   - 反向通路(Direct_Back_Path=1, select=1): FIFO数据 -> rdata_to_DRAM
// ============================================================================

module demuxx #(parameter FIFO_WIDTH = 64)  // 数据位宽（默认64位，与FIFO一致）
(
    input wire [FIFO_WIDTH-1:0] in,         // 输入数据（FIFO读出的原始数据）
    input wire select,                       // 选择信号: 0=输出到out0(GLB侧), 1=输出到out1(DRAM侧)
    output wire [FIFO_WIDTH-1:0] out0,       // 输出0 -> GLB方向 (select=0时有效)
    output wire [FIFO_WIDTH-1:0] out1        // 输出1 -> DRAM方向 (select=1时有效)
);

    // select=0: in转发到out0(GLB), out1置0
    // select=1: in转发到out1(DRAM), out0置0
    assign out0 = (~select) ? in : 'b0;
    assign out1 = (select) ? in : 'b0;

endmodule
