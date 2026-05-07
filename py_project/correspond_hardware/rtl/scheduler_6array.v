// ===========================================================================
// Scheduler_6array.v — 6阵列RS调度器 (全posedge, nxt_state驱动)
// ===========================================================================
// 对应Python: ed_run/scheduler.py — 6个PE阵列并行处理一行输出的18像素段
//
// 数据分布 (ifs_row = [pad_left, row[0..15], pad_right], 共18元素):
//   data_port0 = ifs_row[0:5]   → 阵列0输出像素 0,1,2
//   data_port1 = ifs_row[3:8]   → 阵列1输出像素 3,4,5
//   data_port2 = ifs_row[6:11]  → 阵列2输出像素 6,7,8
//   data_port3 = ifs_row[9:14]  → 阵列3输出像素 9,10,11
//   data_port4 = ifs_row[12:17] → 阵列4输出像素 12,13,14
//   data_port5 = ifs_row[13:18] → 阵列5输出像素 13,14,15 (仅像素15有效)
//
// 一行ifmap = 16个Q8值, 输入为16元素向量 + padding
// ===========================================================================

`timescale 1ns / 1ps

module Scheduler_6array #(
    parameter IN_WIDTH  = 5,
    parameter W_WIDTH   = 8,
    parameter ACC_WIDTH = 16,
    parameter IFMAP_W   = 16   // ifmap宽度 (列数)
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start_tile,

    // 一行ifmap (16个Q8值) — 外部需提供含padding的18元素向量
    input  wire [ IN_WIDTH*18 -1 : 0]    ifmap_row_padded,  // [pad, col0..15, pad]

    // 3行滤波器 (每行3个值)
    input  wire [  W_WIDTH*3 -1 : 0]     filter_row0,
    input  wire [  W_WIDTH*3 -1 : 0]     filter_row1,
    input  wire [  W_WIDTH*3 -1 : 0]     filter_row2,
    input  wire [ ACC_WIDTH*3 -1 : 0]    psum_top,

    // 6个start_global (每阵列一个)
    output reg                           start_global,     // 所有阵列共享start
    output reg                           new_in_data,
    // 6个数据端口 (每阵列5个值)
    output reg  [ IN_WIDTH*5 -1 : 0]     out_data0,
    output reg  [ IN_WIDTH*5 -1 : 0]     out_data1,
    output reg  [ IN_WIDTH*5 -1 : 0]     out_data2,
    output reg  [ IN_WIDTH*5 -1 : 0]     out_data3,
    output reg  [ IN_WIDTH*5 -1 : 0]     out_data4,
    output reg  [ IN_WIDTH*5 -1 : 0]     out_data5,
    output reg  [  W_WIDTH*3 -1 : 0]     out_filter,
    output reg  [ ACC_WIDTH*3 -1 : 0]    out_psum_top,

    // 6个阵列结果+完成信号
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr_result0,
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr_result1,
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr_result2,
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr_result3,
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr_result4,
    input  wire [ ACC_WIDTH*3 -1 : 0]    arr_result5,
    input  wire                          arr_finished0,
    input  wire                          arr_finished1,
    input  wire                          arr_finished2,
    input  wire                          arr_finished3,
    input  wire                          arr_finished4,
    input  wire                          arr_finished5,

    // 输出 (任一阵列完成即通知aggregator)
    output reg                           any_finished,
    output reg                           tile_done
);

    localparam IDLE  = 3'd0;
    localparam FEED0 = 3'd1;
    localparam FEED1 = 3'd2;
    localparam FEED2 = 3'd3;
    localparam DRAIN = 3'd4;
    localparam DONE  = 3'd5;

    reg [2:0] state;
    reg [7:0] drain_cnt;
    wire any_arr_finished;
    assign any_arr_finished = arr_finished0 | arr_finished1 | arr_finished2 |
                              arr_finished3 | arr_finished4 | arr_finished5;

    // ---- 下一状态 (含default防止死锁) ----
    wire [2:0] nxt_state;
    assign nxt_state = (state == IDLE  && start_tile)                 ? FEED0 :
                       (state == IDLE  && !start_tile)                ? IDLE  :
                       (state == FEED0)                               ? FEED1 :
                       (state == FEED1)                               ? FEED2 :
                       (state == FEED2)                               ? DRAIN :
                       (state == DRAIN && (any_arr_finished || drain_cnt > 8'd50)) ? DONE :
                       (state == DRAIN)                               ? DRAIN :
                       (state == DONE)                                ? IDLE  :
                                                                        IDLE;  // default: 回到IDLE

    // ---- 解包ifmap行 (18个值) ----
    wire [IN_WIDTH-1:0] ifs [0:17];
    assign ifs[0]  = ifmap_row_padded[0*IN_WIDTH +: IN_WIDTH];
    assign ifs[1]  = ifmap_row_padded[1*IN_WIDTH +: IN_WIDTH];
    assign ifs[2]  = ifmap_row_padded[2*IN_WIDTH +: IN_WIDTH];
    assign ifs[3]  = ifmap_row_padded[3*IN_WIDTH +: IN_WIDTH];
    assign ifs[4]  = ifmap_row_padded[4*IN_WIDTH +: IN_WIDTH];
    assign ifs[5]  = ifmap_row_padded[5*IN_WIDTH +: IN_WIDTH];
    assign ifs[6]  = ifmap_row_padded[6*IN_WIDTH +: IN_WIDTH];
    assign ifs[7]  = ifmap_row_padded[7*IN_WIDTH +: IN_WIDTH];
    assign ifs[8]  = ifmap_row_padded[8*IN_WIDTH +: IN_WIDTH];
    assign ifs[9]  = ifmap_row_padded[9*IN_WIDTH +: IN_WIDTH];
    assign ifs[10] = ifmap_row_padded[10*IN_WIDTH +: IN_WIDTH];
    assign ifs[11] = ifmap_row_padded[11*IN_WIDTH +: IN_WIDTH];
    assign ifs[12] = ifmap_row_padded[12*IN_WIDTH +: IN_WIDTH];
    assign ifs[13] = ifmap_row_padded[13*IN_WIDTH +: IN_WIDTH];
    assign ifs[14] = ifmap_row_padded[14*IN_WIDTH +: IN_WIDTH];
    assign ifs[15] = ifmap_row_padded[15*IN_WIDTH +: IN_WIDTH];
    assign ifs[16] = ifmap_row_padded[16*IN_WIDTH +: IN_WIDTH];
    assign ifs[17] = ifmap_row_padded[17*IN_WIDTH +: IN_WIDTH];

    // ---- 6个数据端口 = ifs_row的不同5元素切片 ----
    wire [IN_WIDTH*5-1:0] data_slice0, data_slice1, data_slice2, data_slice3, data_slice4, data_slice5;
    assign data_slice0 = {ifs[4], ifs[3], ifs[2], ifs[1], ifs[0]};
    assign data_slice1 = {ifs[7], ifs[6], ifs[5], ifs[4], ifs[3]};
    assign data_slice2 = {ifs[10], ifs[9], ifs[8], ifs[7], ifs[6]};
    assign data_slice3 = {ifs[13], ifs[12], ifs[11], ifs[10], ifs[9]};
    assign data_slice4 = {ifs[16], ifs[15], ifs[14], ifs[13], ifs[12]};
    assign data_slice5 = {ifs[17], ifs[16], ifs[15], ifs[14], ifs[13]};

    // ---- 状态 + 输出寄存器 ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            drain_cnt    <= 8'd0;
            start_global <= 1'b0;
            new_in_data  <= 1'b0;
            out_data0 <= 0; out_data1 <= 0; out_data2 <= 0;
            out_data3 <= 0; out_data4 <= 0; out_data5 <= 0;
            out_filter <= 0; out_psum_top <= 0;
            tile_done <= 1'b0; any_finished <= 1'b0;
        end else begin
            state     <= nxt_state;
            tile_done <= 1'b0;
            any_finished <= 1'b0;
            out_psum_top <= psum_top;

            case (nxt_state)
                IDLE: begin start_global <= 1'b0; new_in_data <= 1'b0; end

                FEED0: begin
                    start_global <= 1'b1; new_in_data <= 1'b1;
                    out_data0 <= data_slice0; out_data1 <= data_slice1;
                    out_data2 <= data_slice2; out_data3 <= data_slice3;
                    out_data4 <= data_slice4; out_data5 <= data_slice5;
                    out_filter <= filter_row0;
                end

                FEED1: begin
                    start_global <= 1'b0; new_in_data <= 1'b1;
                    out_data0 <= data_slice0; out_data1 <= data_slice1;
                    out_data2 <= data_slice2; out_data3 <= data_slice3;
                    out_data4 <= data_slice4; out_data5 <= data_slice5;
                    out_filter <= filter_row1;
                end

                FEED2: begin
                    new_in_data  <= 1'b1;
                    out_data0 <= data_slice0; out_data1 <= data_slice1;
                    out_data2 <= data_slice2; out_data3 <= data_slice3;
                    out_data4 <= data_slice4; out_data5 <= data_slice5;
                    out_filter <= filter_row2;
                end

                DRAIN: begin
                    new_in_data <= 1'b0;
                    if (any_arr_finished) any_finished <= 1'b1;
                end

                DONE: begin
                    tile_done <= 1'b1;
                    new_in_data <= 1'b0;
                end
            endcase

            if (nxt_state == DRAIN) drain_cnt <= drain_cnt + 8'd1;
            else drain_cnt <= 8'd0;
        end
    end

endmodule
