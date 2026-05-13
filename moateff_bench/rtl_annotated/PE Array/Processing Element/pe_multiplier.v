// ============================================================================
// 模块名称: multiplier (有符号乘法器 - 带时钟使能)
// 架构位置: pe.v 内部的乘法器子模块 (MAC流水第1级)
//           pe(PE核心) -> multiplier(本模块) -> truncator -> adder
//
// 模块功能: 执行 16-bit x 16-bit 有符号乘法, 输出 32-bit 乘积
//           - enable=1 且非复位: product = x * y
//           - enable=0 或复位: product = 0
//           - 使用 negedge clk 采样 (与 PE 整体时序一致)
//
// 数据类型: Q0.8 定点有符号数
//           x, y: 16-bit Q0.8 (1符号 + 7整数 + 8小数, 范围[-128,127]/256)
//           product: 32-bit Q0.16 (1符号 + 15整数 + 16小数)
//
// 使能控制: en_mul_r = ~zero_flag & rd_data (一级流水延迟)
//           零值跳过: 当ifmap=0时关闭乘法器, 节省动态功耗
// ============================================================================
module multiplier
#(
    parameter DATA_WIDTH = 16            // 操作数位宽 (默认16)
)(
    input wire clk, reset, enable,       // 时钟, 异步复位(高有效), 使能
    input wire signed [DATA_WIDTH - 1:0] x,     // 有符号乘数 x (ifmap像素)
    input wire signed [DATA_WIDTH - 1:0] y,     // 有符号乘数 y (filter权重)

    output reg signed [2 * DATA_WIDTH - 1:0] product  // 有符号乘积 (32-bit)
);

    // =======================================================================
    // 乘法器时序逻辑
    // always @(negedge clk or posedge reset): 下降沿触发, 异步复位
    // 行为:
    //   reset=1  -> product = 0 (复位输出)
    //   enable=1 -> product = x * y (执行有符号乘法)
    //   enable=0 -> product = 0 (关闭, 节省功耗/保持零)
    // 注意: reset优先于enable; 未使能时也输出0
    // =======================================================================
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            // 复位: 输出清零
            product <= {DATA_WIDTH{1'b0}};    // 扩展为32位零
        end else if (enable) begin
            // 使能: 执行有符号乘法 16-bit x 16-bit -> 32-bit
            product <= x * y;
        end else begin
            // 未使能: 输出零 (零跳过, 节省功耗)
            product <= {DATA_WIDTH{1'b0}};
        end
    end

endmodule
