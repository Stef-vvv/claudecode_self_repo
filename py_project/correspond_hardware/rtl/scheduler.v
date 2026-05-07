// ===========================================================================
// Scheduler.v — RS数据流调度器 (简化版, 单PE阵列, 逐tile处理)
// ===========================================================================
// 对应Python: scheduler.py (简化: 单阵列, 逐tile完整排空)
//
// FSM状态:
//   IDLE → FEED0 → FEED1 → FEED2 → DRAIN → DONE → (next tile) or IDLE
//
// 地址生成 (组合逻辑):
//   ifmap_addr  = ic * H*W + (oh+kh-1)*W + (ow+kw-1)  (含padding处理)
//   filter_addr = oc * C*K*K + ic * K*K + kh*K + kw
//
// 注意: 此版本为单阵列简化版. 完整6阵列版本需扩展data_port宽度和阵列实例.
// ===========================================================================

`timescale 1ns / 1ps

module Scheduler #(
    parameter IN_WIDTH  = 5,
    parameter W_WIDTH   = 8,
    parameter ACC_WIDTH = 16,
    parameter H         = 16,    // IFMAP高度
    parameter W         = 16,    // IFMAP宽度
    parameter C         = 32,    // 输入通道数
    parameter F         = 64,    // 输出通道数
    parameter K         = 3      // 卷积核尺寸
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start_cmd,      // 外部启动命令

    // BRAM读接口 (ifmap)
    output reg  [15:0]                   ifmap_addr,
    input  wire [ IN_WIDTH*16 -1 : 0]    ifmap_rdata,    // 16个Q8值打包 (一行)

    // BRAM读接口 (filter)
    output reg  [15:0]                   filter_addr,
    input  wire [  W_WIDTH*3  -1 : 0]    filter_rdata,   // 3个Q8值打包 (一行)

    // PE Array控制
    output reg                           start_global,
    output reg                           new_in_data,
    output reg  [ IN_WIDTH*5 -1 : 0]     out_data,       // 5个值 (滑窗)
    output reg  [  W_WIDTH*3 -1 : 0]     out_filter,     // 3个值
    output reg  [ ACC_WIDTH*3 -1 : 0]    out_psum_top,

    // PE Array状态
    input  wire [ ACC_WIDTH*3 -1 : 0]    array_result,
    input  wire                          array_finished,

    // 聚合器接口
    output reg  [15:0]                   out_addr,
    output reg                           out_valid,

    // 状态输出
    output reg                           tile_done,
    output reg                           all_done
);

    // ========================================================================
    // FSM状态
    // ========================================================================
    localparam IDLE   = 4'd0;
    localparam FEED0  = 4'd1;   // 广播row0数据+row0滤波器, start_global=1
    localparam FEED1  = 4'd2;   // 广播row1数据+row1滤波器
    localparam FEED2  = 4'd3;   // 广播row2数据+row2滤波器
    localparam DRAIN  = 4'd4;   // 等待阵列完成
    localparam DONE   = 4'd5;   // 捕获结果
    localparam NEXT   = 4'd6;   // 准备下一个tile

    reg [3:0] state, nxt_state;

    // ========================================================================
    // 循环计数器
    // ========================================================================
    reg [5:0]  ic_cnt;        // 输入通道 0..31
    reg [3:0]  tile_cnt;      // tile行 0..5 (skip_row/3)
    reg [6:0]  oc_cnt;        // 输出通道 0..63
    reg [2:0]  feed_cnt;      // 数据喂入计数 0..2
    reg [7:0]  drain_cnt;     // 排空计数

    // 组合地址
    wire [15:0] base_ifmap_addr;
    wire [15:0] base_filter_addr;
    wire [15:0] output_addr;

    // base_ifmap_addr = ic * 16 + row  (row = tile_cnt*3 + feed_cnt, 再减1处理padding)
    // 实际BRAM地址: ic * 16 + (tile_cnt*3 + feed_cnt - 1)
    wire [7:0]  ifmap_row;
    assign ifmap_row = tile_cnt * 3 + feed_cnt;   // 0..19范围
    assign base_ifmap_addr = ic_cnt * H + ifmap_row - 8'd1;  // row-1 (padding处理)

    // base_filter_addr = oc * C*K + ic * K + feed_cnt
    assign base_filter_addr = oc_cnt * (C*K) + ic_cnt * K + {13'd0, feed_cnt};

    // output_addr = oc * H + (tile_cnt*3 + feed_cnt - 1)
    assign output_addr = oc_cnt * H + ifmap_row - 8'd1;

    // ========================================================================
    // FSM组合逻辑
    // ========================================================================
    always @(*) begin
        nxt_state = state;
        case (state)
            IDLE:  if (start_cmd)              nxt_state = FEED0;
            FEED0:                              nxt_state = FEED1;
            FEED1:                              nxt_state = FEED2;
            FEED2:                              nxt_state = DRAIN;
            DRAIN: if (array_finished || drain_cnt > 8'd20) nxt_state = DONE;
            DONE:                               nxt_state = NEXT;
            NEXT:                               nxt_state = IDLE;  // 或继续下一个tile
        endcase
    end

    // ========================================================================
    // 时序逻辑
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            ic_cnt       <= 6'd0;
            tile_cnt     <= 4'd0;
            oc_cnt       <= 7'd0;
            feed_cnt     <= 3'd0;
            drain_cnt    <= 8'd0;
            start_global <= 1'b0;
            new_in_data  <= 1'b0;
            out_data     <= 0;
            out_filter   <= 0;
            out_psum_top <= 0;
            out_addr     <= 16'd0;
            out_valid    <= 1'b0;
            tile_done    <= 1'b0;
            all_done     <= 1'b0;
            ifmap_addr   <= 16'd0;
            filter_addr  <= 16'd0;
        end else begin
            state     <= nxt_state;
            out_valid <= 1'b0;
            tile_done <= 1'b0;

            case (state)
                IDLE: begin
                    start_global <= 1'b0;
                    new_in_data  <= 1'b0;
                    if (start_cmd) begin
                        feed_cnt  <= 3'd0;
                        drain_cnt <= 8'd0;
                        // 设置ifmap地址 (ic*16 + row, padding处理)
                        ifmap_addr <= base_ifmap_addr;
                        filter_addr <= base_filter_addr;
                    end
                end

                FEED0: begin
                    feed_cnt     <= 3'd1;
                    start_global <= 1'b1;   // 仅T0发start脉冲
                    new_in_data  <= 1'b1;
                    // ifmap数据已在总线上 (前一状态设置地址, 本周期数据有效)
                    // 注: 实际系统需要BRAM读延迟, 这里简化为组合读
                    out_data   <= ifmap_rdata[IN_WIDTH*5-1:0];    // 取前5个值
                    out_filter <= filter_rdata;
                    out_psum_top <= 0;
                    ifmap_addr  <= base_ifmap_addr;
                    filter_addr <= base_filter_addr;
                end

                FEED1: begin
                    feed_cnt     <= 3'd2;
                    start_global <= 1'b0;
                    // new_in_data保持1 (后续PE通过start传播锁存)
                    out_data   <= ifmap_rdata[IN_WIDTH*5-1:0];
                    out_filter <= filter_rdata;
                    ifmap_addr  <= base_ifmap_addr;
                    filter_addr <= base_filter_addr;
                end

                FEED2: begin
                    feed_cnt     <= 3'd0;
                    new_in_data  <= 1'b0;    // 停止数据锁存
                    out_data   <= ifmap_rdata[IN_WIDTH*5-1:0];
                    out_filter <= filter_rdata;
                end

                DRAIN: begin
                    new_in_data <= 1'b0;
                    drain_cnt   <= drain_cnt + 8'd1;
                    if (array_finished) begin
                        // 不在这里设out_valid, DONE状态处理
                    end
                end

                DONE: begin
                    out_addr  <= output_addr;
                    out_valid <= 1'b1;
                    tile_done <= 1'b1;
                end

                NEXT: begin
                    // 循环控制: 先遍历oc, 再遍历tile, 再遍历ic
                    if (oc_cnt < F - 1) begin
                        oc_cnt <= oc_cnt + 7'd1;
                        nxt_state <= FEED0;  // 覆盖默认的NEXT→IDLE
                    end else begin
                        oc_cnt <= 7'd0;
                        if (tile_cnt < 4'd5) begin    // 6个tile (0..5)
                            tile_cnt <= tile_cnt + 4'd1;
                            nxt_state <= FEED0;
                        end else begin
                            tile_cnt <= 4'd0;
                            if (ic_cnt < C - 1) begin
                                ic_cnt <= ic_cnt + 6'd1;
                                nxt_state <= FEED0;
                            end else begin
                                ic_cnt <= 6'd0;
                                all_done <= 1'b1;
                                nxt_state <= IDLE;
                            end
                        end
                    end
                end
            endcase
        end
    end

endmodule
