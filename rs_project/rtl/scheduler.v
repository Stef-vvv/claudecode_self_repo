// ===========================================================================
// Scheduler.v — RS Tile调度器 (全posedge clk, nxt_state驱动输出)
// ===========================================================================
// 对应Python: ed_run/scheduler.py — 单tile RS时序
//
// 关键设计: 输出由nxt_state(组合逻辑)决定, 在posedge寄存.
// PE在下个posedge采样 → 看到的是上一拍寄存的稳定值.
//
// 时序:
//   posedge0: IDLE+start_tile → nxt_state=FEED0, 输出: start=1,ni_d=1,row0
//   posedge1: PE(0,0)采样start+row0, 输出变为: start=0,ni_d=1,row1
//   posedge2: PE(1,0)采样(row1已在总线), 输出变为: ni_d=1,row2
//   posedge3: PE(2,0)采样(row2已在总线), 输出变为: ni_d=0
//   posedge4+: DRAIN等待完成
// ===========================================================================

`timescale 1ns / 1ps

module Scheduler #(
    parameter IN_WIDTH  = 5,
    parameter W_WIDTH   = 8,
    parameter ACC_WIDTH = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start_tile,

    input  wire [ IN_WIDTH*5 -1 : 0]     ifmap_row0,
    input  wire [ IN_WIDTH*5 -1 : 0]     ifmap_row1,
    input  wire [ IN_WIDTH*5 -1 : 0]     ifmap_row2,
    input  wire [  W_WIDTH*3 -1 : 0]     filter_row0,
    input  wire [  W_WIDTH*3 -1 : 0]     filter_row1,
    input  wire [  W_WIDTH*3 -1 : 0]     filter_row2,
    input  wire [ ACC_WIDTH*3 -1 : 0]    psum_top,

    output reg                           start_global,
    output reg                           new_in_data,
    output reg  [ IN_WIDTH*5 -1 : 0]     out_data,
    output reg  [  W_WIDTH*3 -1 : 0]     out_filter,
    output reg  [ ACC_WIDTH*3 -1 : 0]    out_psum_top,

    input  wire [ ACC_WIDTH*3 -1 : 0]    array_result,
    input  wire                          array_finished,

    output reg  [ ACC_WIDTH*3 -1 : 0]    tile_result,
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

    // ---- 下一状态 (组合逻辑) ----
    wire [2:0] nxt_state;
    assign nxt_state = (state == IDLE  && start_tile)                      ? FEED0 :
                       (state == IDLE  && !start_tile)                     ? IDLE  :
                       (state == FEED0)                                    ? FEED1 :
                       (state == FEED1)                                    ? FEED2 :
                       (state == FEED2)                                    ? DRAIN :
                       (state == DRAIN && (array_finished || drain_cnt > 8'd50)) ? DONE :
                       (state == DRAIN)                                    ? DRAIN :
                       (state == DONE)                                     ? IDLE  :
                                                                             IDLE;

    // ---- 状态寄存器 + 输出寄存器 (全部posedge) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            drain_cnt    <= 8'd0;
            start_global <= 1'b0;
            new_in_data  <= 1'b0;
            out_data     <= 0;
            out_filter   <= 0;
            out_psum_top <= 0;
            tile_result  <= 0;
            tile_done    <= 1'b0;
        end else begin
            // 状态更新
            state     <= nxt_state;
            tile_done <= 1'b0;
            out_psum_top <= psum_top;

            // 输出 = f(nxt_state): 寄存后下一拍PE采样
            case (nxt_state)
                IDLE: begin
                    start_global <= 1'b0;
                    new_in_data  <= 1'b0;
                end

                FEED0: begin
                    start_global <= 1'b1;
                    new_in_data  <= 1'b1;
                    out_data     <= ifmap_row0;
                    out_filter   <= filter_row0;
                end

                FEED1: begin
                    start_global <= 1'b0;
                    new_in_data  <= 1'b1;
                    out_data     <= ifmap_row1;
                    out_filter   <= filter_row1;
                end

                FEED2: begin
                    new_in_data <= 1'b1;
                    out_data    <= ifmap_row2;
                    out_filter  <= filter_row2;
                end

                DRAIN: begin
                    new_in_data <= 1'b0;
                end

                DONE: begin
                    tile_result <= array_result;
                    tile_done   <= 1'b1;
                    new_in_data <= 1'b0;
                end
            endcase

            // 排空计数
            if (nxt_state == DRAIN)
                drain_cnt <= drain_cnt + 8'd1;
            else
                drain_cnt <= 8'd0;
        end
    end

endmodule
