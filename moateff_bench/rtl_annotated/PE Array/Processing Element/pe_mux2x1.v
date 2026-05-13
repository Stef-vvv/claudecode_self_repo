// ============================================================================
// 模块名称: mux2x1 (二选一多路选择器 / 2:1 Multiplexer)
// 架构位置: pe.v 内部的通用数据选择子模块
//           pe(PE核心) -> mux2x1(本模块) 共3个实例
//
// 模块功能: 组合逻辑2选1选择器
//           sel=0: out = in0
//           sel=1: out = in1
//
// 在 pe.v 中的3个实例:
//   mux1: psum数据转发选择
//         in0 = SPAD读出 (pusm_from_spad_w)
//         in1 = 加法器输出 (sum_result, 转发绕行)
//         sel = forward (同地址写读冲突)
//
//   mux2: 累加复位选择
//         in0 = 经转发的psum (pusm_from_spad)
//         in1 = 0 (全零, 累加复位值)
//         sel = reset_accumulation_r
//
//   mux3: 加法器输入源选择
//         in0 = 截断结果 (truncated_result, 本PE乘法结果)
//         in1 = 外部ipsum (ipsum_pixel, 累加模式)
//         sel = accumulate_ipsum_rr
// ============================================================================
module mux2x1
#(
    parameter DATA_WIDTH = 16            // 数据宽度 (可参数化, 默认16)
)(
    input  [DATA_WIDTH-1:0] in0,         // 输入0: sel=0时选择
    input  [DATA_WIDTH-1:0] in1,         // 输入1: sel=1时选择
    input                    sel,        // 选择信号: 0=in0, 1=in1

    output [DATA_WIDTH-1:0] out          // 输出 = sel ? in1 : in0
);

    // 纯组合逻辑: 三目运算符实现2选1
    assign out = sel ? in1 : in0;

endmodule

