// ===========================================================================
// aggregator_6array.v — 6阵列聚合器 (按MD规范: 18→16像素拼接)
// ===========================================================================
// 对应Python: aggregator.py — Aggregator.process()
//
// 拼接规则:
//   output[0:2]   = arr0.result[0:2] + prev[0:2]
//   output[3:5]   = arr1.result[0:2] + prev[3:5]
//   output[6:8]   = arr2.result[0:2] + prev[6:8]
//   output[9:11]  = arr3.result[0:2] + prev[9:11]
//   output[12:14] = arr4.result[0:2] + prev[12:14]
//   output[15]    = arr5.result[2]   + prev[15]    (仅取阵列5的第3像素)
//
// 阵列5的前2个输出与阵列4重叠(c13,c14), 被丢弃.
// ===========================================================================

`timescale 1ns / 1ps

module aggregator_6array #(
    parameter ACC_WIDTH = 16,
    parameter OUT_WIDTH = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          capture,        // 捕获使能 (来自scheduler tile_done或any_finished)

    // 6阵列结果 (每阵列3值)
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr0_result,
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr1_result,
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr2_result,
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr3_result,
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr4_result,
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr5_result,

    // 先前部分和 (从BRAM读取, 跨input_channel累加)
    input  wire [ ACC_WIDTH*OUT_WIDTH -1 : 0] prev_partial,

    // 输出 (16像素行)
    output reg  [ ACC_WIDTH*OUT_WIDTH -1 : 0] acc_result,
    output reg                                acc_valid
);

    // ---- 解包阵列结果 (每阵列3值) ----
    wire [ACC_WIDTH-1:0] a0_0, a0_1, a0_2;  // arr0
    wire [ACC_WIDTH-1:0] a1_0, a1_1, a1_2;  // arr1
    wire [ACC_WIDTH-1:0] a2_0, a2_1, a2_2;  // arr2
    wire [ACC_WIDTH-1:0] a3_0, a3_1, a3_2;  // arr3
    wire [ACC_WIDTH-1:0] a4_0, a4_1, a4_2;  // arr4
    wire [ACC_WIDTH-1:0] a5_0, a5_1, a5_2;  // arr5

    assign a0_0 = arr0_result[0*ACC_WIDTH +: ACC_WIDTH];
    assign a0_1 = arr0_result[1*ACC_WIDTH +: ACC_WIDTH];
    assign a0_2 = arr0_result[2*ACC_WIDTH +: ACC_WIDTH];
    assign a1_0 = arr1_result[0*ACC_WIDTH +: ACC_WIDTH];
    assign a1_1 = arr1_result[1*ACC_WIDTH +: ACC_WIDTH];
    assign a1_2 = arr1_result[2*ACC_WIDTH +: ACC_WIDTH];
    assign a2_0 = arr2_result[0*ACC_WIDTH +: ACC_WIDTH];
    assign a2_1 = arr2_result[1*ACC_WIDTH +: ACC_WIDTH];
    assign a2_2 = arr2_result[2*ACC_WIDTH +: ACC_WIDTH];
    assign a3_0 = arr3_result[0*ACC_WIDTH +: ACC_WIDTH];
    assign a3_1 = arr3_result[1*ACC_WIDTH +: ACC_WIDTH];
    assign a3_2 = arr3_result[2*ACC_WIDTH +: ACC_WIDTH];
    assign a4_0 = arr4_result[0*ACC_WIDTH +: ACC_WIDTH];
    assign a4_1 = arr4_result[1*ACC_WIDTH +: ACC_WIDTH];
    assign a4_2 = arr4_result[2*ACC_WIDTH +: ACC_WIDTH];
    assign a5_0 = arr5_result[0*ACC_WIDTH +: ACC_WIDTH];
    assign a5_1 = arr5_result[1*ACC_WIDTH +: ACC_WIDTH];
    assign a5_2 = arr5_result[2*ACC_WIDTH +: ACC_WIDTH];

    // ---- 解包先前部分和 (16值) ----
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

    // ---- 拼接+累加 (组合逻辑) ----
    wire [ACC_WIDTH-1:0] out [0:15];
    assign out[0]  = a0_0 + pp[0];
    assign out[1]  = a0_1 + pp[1];
    assign out[2]  = a0_2 + pp[2];
    assign out[3]  = a1_0 + pp[3];
    assign out[4]  = a1_1 + pp[4];
    assign out[5]  = a1_2 + pp[5];
    assign out[6]  = a2_0 + pp[6];
    assign out[7]  = a2_1 + pp[7];
    assign out[8]  = a2_2 + pp[8];
    assign out[9]  = a3_0 + pp[9];
    assign out[10] = a3_1 + pp[10];
    assign out[11] = a3_2 + pp[11];
    assign out[12] = a4_0 + pp[12];
    assign out[13] = a4_1 + pp[13];
    assign out[14] = a4_2 + pp[14];
    assign out[15] = a5_2 + pp[15];  // 阵列5只取第3个像素

    // ---- 时序逻辑 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_result <= 0;
            acc_valid  <= 1'b0;
        end else begin
            acc_valid <= 1'b0;
            if (capture) begin
                acc_result <= {out[15],out[14],out[13],out[12],out[11],
                               out[10],out[9], out[8], out[7], out[6],
                               out[5], out[4], out[3], out[2], out[1], out[0]};
                acc_valid <= 1'b1;
            end
        end
    end

endmodule
