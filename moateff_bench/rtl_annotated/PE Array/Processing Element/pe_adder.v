// ============================================================================
// 模块名称: adder (组合逻辑加法器)
// 架构位置: pe.v 内部的加法器子模块 (MAC流水第3级, 最后一级)
//           pe(PE核心) -> multiplier -> truncator -> adder(本模块)
//
// 模块功能: 执行两个 16-bit 有符号数的加法, 纯组合逻辑 (无时序)
//           sum = x + y
//
// 数据类型: Q0.8 定点有符号数 (16-bit)
//   输入x: 乘法截断结果(truncated_result) 或 外部ipsum(ipsum_pixel)
//   输入y: 旧部分和 (经转发MUX和累加复位MUX处理)
//   输出:  新部分和 (增量 + 旧值)
//
// 注意事项:
//   - 纯组合逻辑, 无流水寄存器 (流水由调用方 pe.v 的reg3管理)
//   - 溢出不处理, 依赖Q0.8格式保证不溢出 (输入范围受限)
// ============================================================================
module adder
#(
    parameter DATA_WIDTH = 16            // 操作数位宽 (默认16)
)(
    input  wire signed [DATA_WIDTH - 1:0] x,   // 有符号加数 x (截断结果/ipsum)
    input  wire signed [DATA_WIDTH - 1:0] y,   // 有符号加数 y (旧部分和)
    output wire signed [DATA_WIDTH - 1:0] sum  // 有符号和 = x + y (新部分和)
);

    // 纯组合逻辑: sum = x + y
    assign sum = x + y;

endmodule
