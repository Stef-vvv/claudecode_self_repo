// =============================================================================
// 模块名称: sync_fifo_flag_generator (同步FIFO标志/脉冲展宽器)
// 功能描述: 将外部请求信号(enable)展宽为多周期脉冲(flag)。
//           用于sync_fifo_wrapper中的宽度转换节流:
//           当读写宽度不同时, 需要多个写周期填充一个读单元(或反之),
//           通过此模块将单次请求展宽为持续的flag信号。
// 工作原理:
//   - flag = (count_r != 0) | enable: 有累积计数或有新请求时输出1
//   - flag=1时 count_r递增: 展宽WIDTH拍
//   - count_r在flag=0时保持
//   本质上是一个"欠债"计数器: enable脉冲注入WIDTH个节拍,
//   通过flag=1逐拍消耗, 直到count_r归零。
// =============================================================================

module sync_fifo_flag_generator #(
    // 展宽拍数位宽
    parameter WIDTH = 8
)(
    input wire clk, reset,
    input wire enable,          // 外部请求脉冲
    output wire flag            // 展宽输出
);

    // 累积计数器: 记录还需要输出的拍数
    reg [WIDTH-1:0] count_r;

    // ---- 时序逻辑: 计数器 ----
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            count_r <= {WIDTH{1'b0}};         // 复位归零
        end else if (flag) begin
            count_r <= count_r + 1'b1;        // flag=1时递增(消耗一个节拍)
        end
    end

    // flag = (count_r != 0) | enable
    //   有累积"欠债"或新请求时, flag=1
    assign flag = (count_r != 0) | enable;

endmodule
