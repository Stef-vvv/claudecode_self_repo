// ===========================================================================
// Aggregator.v — 部分和累加器 (单PE阵列, 无for/generate)
// ===========================================================================
// 对应Python: ed_run/aggregator.py — Aggregator.process()
//
// 功能: 接收PE阵列输出, 与先前部分和累加, 产生最终结果.
// 单阵列版本: 直接累加3个输出像素.
// 6阵列版本需扩展: 拼接6×3=18像素为16像素行.
// ===========================================================================

`timescale 1ns / 1ps

module Aggregator #(
    parameter ACC_WIDTH = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,

    // PE Array输出
    input  wire [ ACC_WIDTH*3 -1 : 0]    array_result,
    input  wire                          array_finished,

    // 先前部分和 (来自BRAM或前次累加)
    input  wire [ ACC_WIDTH*3 -1 : 0]    prev_partial,

    // 累加输出
    output reg  [ ACC_WIDTH*3 -1 : 0]    acc_result,
    output reg                           acc_valid
);

    // 解包信号
    wire [ACC_WIDTH-1:0] ar0, ar1, ar2;  // array_result
    wire [ACC_WIDTH-1:0] pp0, pp1, pp2;  // prev_partial

    assign ar0 = array_result[0*ACC_WIDTH +: ACC_WIDTH];
    assign ar1 = array_result[1*ACC_WIDTH +: ACC_WIDTH];
    assign ar2 = array_result[2*ACC_WIDTH +: ACC_WIDTH];
    assign pp0 = prev_partial[0*ACC_WIDTH +: ACC_WIDTH];
    assign pp1 = prev_partial[1*ACC_WIDTH +: ACC_WIDTH];
    assign pp2 = prev_partial[2*ACC_WIDTH +: ACC_WIDTH];

    // 累加结果
    wire [ACC_WIDTH-1:0] sum0, sum1, sum2;
    assign sum0 = ar0 + pp0;
    assign sum1 = ar1 + pp1;
    assign sum2 = ar2 + pp2;

    // ---- 时序逻辑 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_result <= 0;
            acc_valid  <= 1'b0;
        end else begin
            acc_valid <= 1'b0;
            if (array_finished) begin
                acc_result <= {sum2, sum1, sum0};
                acc_valid  <= 1'b1;
            end
        end
    end

endmodule
