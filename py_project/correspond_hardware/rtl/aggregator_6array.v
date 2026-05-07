// ===========================================================================
// Aggregator_6array.v — 6阵列聚合器 (18像素→16像素行, 无for/generate)
// ===========================================================================
// 对应Python: ed_run/aggregator.py — 6阵列拼接+BRAM累加
//
// 拼接规则 (匹配Python):
//   output[0:2]   = array0.output[0:2]
//   output[3:5]   = array1.output[0:2]
//   output[6:8]   = array2.output[0:2]
//   output[9:11]  = array3.output[0:2]
//   output[12:14] = array4.output[0:2]
//   output[15]    = array5.output[2]      (仅第3个像素, 前2个与array4重叠)
// ===========================================================================

`timescale 1ns / 1ps

module Aggregator_6array #(
    parameter ACC_WIDTH = 16,
    parameter OUT_WIDTH = 16   // 一行16个像素
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          process_trigger,  // 来自scheduler的any_finished

    // 6个阵列结果 (每阵列3个值)
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr0_result,
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr1_result,
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr2_result,
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr3_result,
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr4_result,
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr5_result,

    // 6个完成信号
    input  wire                          arr0_finished,
    input  wire                          arr1_finished,
    input  wire                          arr2_finished,
    input  wire                          arr3_finished,
    input  wire                          arr4_finished,
    input  wire                          arr5_finished,

    // 先前部分和 (16个值)
    input  wire [ ACC_WIDTH*OUT_WIDTH -1 : 0] prev_partial,

    // 累加输出 (16个值)
    output reg  [ ACC_WIDTH*OUT_WIDTH -1 : 0] acc_result,
    output reg                                acc_valid
);

    // ---- 解包: 6阵列结果 (每阵列3个值) ----
    wire [ACC_WIDTH-1:0] a0r0, a0r1, a0r2;
    wire [ACC_WIDTH-1:0] a1r0, a1r1, a1r2;
    wire [ACC_WIDTH-1:0] a2r0, a2r1, a2r2;
    wire [ACC_WIDTH-1:0] a3r0, a3r1, a3r2;
    wire [ACC_WIDTH-1:0] a4r0, a4r1, a4r2;
    wire [ACC_WIDTH-1:0] a5r0, a5r1, a5r2;

    assign a0r0 = arr0_result[0*ACC_WIDTH +: ACC_WIDTH];
    assign a0r1 = arr0_result[1*ACC_WIDTH +: ACC_WIDTH];
    assign a0r2 = arr0_result[2*ACC_WIDTH +: ACC_WIDTH];
    assign a1r0 = arr1_result[0*ACC_WIDTH +: ACC_WIDTH];
    assign a1r1 = arr1_result[1*ACC_WIDTH +: ACC_WIDTH];
    assign a1r2 = arr1_result[2*ACC_WIDTH +: ACC_WIDTH];
    assign a2r0 = arr2_result[0*ACC_WIDTH +: ACC_WIDTH];
    assign a2r1 = arr2_result[1*ACC_WIDTH +: ACC_WIDTH];
    assign a2r2 = arr2_result[2*ACC_WIDTH +: ACC_WIDTH];
    assign a3r0 = arr3_result[0*ACC_WIDTH +: ACC_WIDTH];
    assign a3r1 = arr3_result[1*ACC_WIDTH +: ACC_WIDTH];
    assign a3r2 = arr3_result[2*ACC_WIDTH +: ACC_WIDTH];
    assign a4r0 = arr4_result[0*ACC_WIDTH +: ACC_WIDTH];
    assign a4r1 = arr4_result[1*ACC_WIDTH +: ACC_WIDTH];
    assign a4r2 = arr4_result[2*ACC_WIDTH +: ACC_WIDTH];
    assign a5r0 = arr5_result[0*ACC_WIDTH +: ACC_WIDTH];
    assign a5r1 = arr5_result[1*ACC_WIDTH +: ACC_WIDTH];
    assign a5r2 = arr5_result[2*ACC_WIDTH +: ACC_WIDTH];

    // ---- 解包: 先前部分和 (16个值) ----
    wire [ACC_WIDTH-1:0] pp [0:15];
    assign pp[0]  = prev_partial[0*ACC_WIDTH +: ACC_WIDTH];
    assign pp[1]  = prev_partial[1*ACC_WIDTH +: ACC_WIDTH];
    assign pp[2]  = prev_partial[2*ACC_WIDTH +: ACC_WIDTH];
    assign pp[3]  = prev_partial[3*ACC_WIDTH +: ACC_WIDTH];
    assign pp[4]  = prev_partial[4*ACC_WIDTH +: ACC_WIDTH];
    assign pp[5]  = prev_partial[5*ACC_WIDTH +: ACC_WIDTH];
    assign pp[6]  = prev_partial[6*ACC_WIDTH +: ACC_WIDTH];
    assign pp[7]  = prev_partial[7*ACC_WIDTH +: ACC_WIDTH];
    assign pp[8]  = prev_partial[8*ACC_WIDTH +: ACC_WIDTH];
    assign pp[9]  = prev_partial[9*ACC_WIDTH +: ACC_WIDTH];
    assign pp[10] = prev_partial[10*ACC_WIDTH +: ACC_WIDTH];
    assign pp[11] = prev_partial[11*ACC_WIDTH +: ACC_WIDTH];
    assign pp[12] = prev_partial[12*ACC_WIDTH +: ACC_WIDTH];
    assign pp[13] = prev_partial[13*ACC_WIDTH +: ACC_WIDTH];
    assign pp[14] = prev_partial[14*ACC_WIDTH +: ACC_WIDTH];
    assign pp[15] = prev_partial[15*ACC_WIDTH +: ACC_WIDTH];

    // ---- 拼接: 18像素→16像素 + 累加先前部分和 ----
    wire [ACC_WIDTH-1:0] out [0:15];
    assign out[0]  = a0r0 + pp[0];
    assign out[1]  = a0r1 + pp[1];
    assign out[2]  = a0r2 + pp[2];
    assign out[3]  = a1r0 + pp[3];
    assign out[4]  = a1r1 + pp[4];
    assign out[5]  = a1r2 + pp[5];
    assign out[6]  = a2r0 + pp[6];
    assign out[7]  = a2r1 + pp[7];
    assign out[8]  = a2r2 + pp[8];
    assign out[9]  = a3r0 + pp[9];
    assign out[10] = a3r1 + pp[10];
    assign out[11] = a3r2 + pp[11];
    assign out[12] = a4r0 + pp[12];
    assign out[13] = a4r1 + pp[13];
    assign out[14] = a4r2 + pp[14];
    assign out[15] = a5r2 + pp[15];  // 仅阵列5的第3个像素

    // ---- 时序逻辑 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_result <= 0;
            acc_valid  <= 1'b0;
        end else begin
            acc_valid <= 1'b0;
            if (process_trigger) begin
                // 打包16个输出值
                acc_result <= {out[15], out[14], out[13], out[12], out[11],
                               out[10], out[9],  out[8],  out[7],  out[6],
                               out[5],  out[4],  out[3],  out[2],  out[1],  out[0]};
                acc_valid <= 1'b1;
            end
        end
    end

endmodule
