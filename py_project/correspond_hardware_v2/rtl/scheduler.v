// ===========================================================================
// Scheduler.v — RS Tile调度器 (输出在negedge更新, posedge前稳定)
// ===========================================================================
// 关键时序: 输出在negedge clk更新 → 在下一个posedge前已稳定 → PE正确采样.
// 状态机在posedge转换, 输出在negedge反映新状态的值.
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
    localparam FEED0 = 3'd1;   // row0+start+new_in_data
    localparam FEED1 = 3'd2;   // row1
    localparam FEED2 = 3'd3;   // row2, 清new_in_data
    localparam DRAIN = 3'd4;   // 等待完成
    localparam DONE  = 3'd5;

    reg [2:0] state, nxt_state;
    reg [7:0] drain_cnt;

    // ---- FSM状态转换 (posedge) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            drain_cnt <= 8'd0;
        end else begin
            state     <= nxt_state;
            if (state == DRAIN)
                drain_cnt <= drain_cnt + 8'd1;
            else
                drain_cnt <= 8'd0;
        end
    end

    always @(*) begin
        nxt_state = state;
        case (state)
            IDLE:  if (start_tile)                      nxt_state = FEED0;
            FEED0:                                      nxt_state = FEED1;
            FEED1:                                      nxt_state = FEED2;
            FEED2:                                      nxt_state = DRAIN;
            DRAIN: if (array_finished || drain_cnt > 8'd50) nxt_state = DONE;
            DONE:                                       nxt_state = IDLE;
        endcase
    end

    // ---- 输出更新 (negedge, 在下一个posedge前稳定) ----
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_global <= 1'b0;
            new_in_data  <= 1'b0;
            out_data     <= 0;
            out_filter   <= 0;
            out_psum_top <= 0;
            tile_result  <= 0;
            tile_done    <= 1'b0;
        end else begin
            // 默认值
            start_global <= 1'b0;
            tile_done    <= 1'b0;
            out_psum_top <= psum_top;

            case (state)
                IDLE: begin
                    new_in_data <= 1'b0;
                end

                FEED0: begin
                    start_global <= 1'b1;
                    new_in_data  <= 1'b1;
                    out_data     <= ifmap_row0;
                    out_filter   <= filter_row0;
                end

                FEED1: begin
                    new_in_data <= 1'b1;
                    out_data    <= ifmap_row1;
                    out_filter  <= filter_row1;
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
        end
    end

endmodule
