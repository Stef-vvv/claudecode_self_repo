// ===========================================================================
// scheduler_6array.v — 6阵列RS调度器 (按MD规范: 6×PE_Array并行)
// ===========================================================================
// MD数据流: for ic: for tile: for oc: feed 3 ifmap rows + 3 filter rows → 6 arrays
//
// 单tile FSM: IDLE→PRELOAD→FEED0→FEED1→FEED2→DRAIN→DONE
// 输出由nxt_state驱动: 在posedge寄存, 下一拍PE采样.
//
// 数据分布 (6阵列, 每阵列独立5元素数据端口):
//   port0 = ifs_row[0:5]   (pad_left, c0, c1, c2, c3)      → 输出像素 0,1,2
//   port1 = ifs_row[3:8]   (c2, c3, c4, c5, c6)             → 输出像素 3,4,5
//   port2 = ifs_row[6:11]  (c5, c6, c7, c8, c9)             → 输出像素 6,7,8
//   port3 = ifs_row[9:14]  (c8, c9, c10, c11, c12)           → 输出像素 9,10,11
//   port4 = ifs_row[12:17] (c11, c12, c13, c14, c15)         → 输出像素 12,13,14
//   port5 = ifs_row[13:18] (c12, c13, c14, c15, pad_right)    → 输出像素 15
//
// 完整conv2循环: 外部需提供ic/tile/oc计数和BRAM读数据.
// 本模块负责: tile内RS时序 + 数据分配 + 控制信号生成.
// ===========================================================================

`timescale 1ns / 1ps

module scheduler_6array #(
    parameter IN_WIDTH  = 5,
    parameter W_WIDTH   = 8,
    parameter ACC_WIDTH = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start_tile,     // 启动单tile

    // ifmap行 (18个Q8值: pad+16cols+pad) — 由外部地址发生器提供
    input  wire [ IN_WIDTH*18 -1 : 0]    ifmap_row_padded,

    // 3行滤波器 (每行3个Q8值) — 由外部地址发生器提供
    input  wire [  W_WIDTH*3 -1 : 0]     filter_row0,
    input  wire [  W_WIDTH*3 -1 : 0]     filter_row1,
    input  wire [  W_WIDTH*3 -1 : 0]     filter_row2,
    input  wire [ ACC_WIDTH*3 -1 : 0]    psum_top,       // 顶部部分和 (=0)

    // 6阵列控制输出
    output reg                           start_global,   // 所有阵列共享start脉冲
    output reg                           new_in_data,    // 数据有效使能
    output reg  [ IN_WIDTH*5 -1 : 0]     out_data0,      // 阵列0数据端口
    output reg  [ IN_WIDTH*5 -1 : 0]     out_data1,      // 阵列1数据端口
    output reg  [ IN_WIDTH*5 -1 : 0]     out_data2,
    output reg  [ IN_WIDTH*5 -1 : 0]     out_data3,
    output reg  [ IN_WIDTH*5 -1 : 0]     out_data4,
    output reg  [ IN_WIDTH*5 -1 : 0]     out_data5,
    output reg  [  W_WIDTH*3 -1 : 0]     out_filter,     // 共享滤波器总线
    output reg  [ ACC_WIDTH*3 -1 : 0]    out_psum_top,   // 共享部分和顶部

    // 6阵列状态输入
    input  wire                          arr_any_finished, // 任一阵列完成 (组合OR)

    // Tile完成
    output reg                           tile_done
);

    localparam IDLE    = 3'd0;
    localparam PRELOAD = 3'd1;  // 预加载row0到总线
    localparam FEED0   = 3'd2;  // start+new_in_data, row0稳定
    localparam FEED1   = 3'd3;  // row1→总线
    localparam FEED2   = 3'd4;  // row2→总线, 清new_in_data
    localparam DRAIN   = 3'd5;  // 等待任意阵列完成
    localparam DONE    = 3'd6;  // 完成

    reg [2:0] state;
    reg [7:0] drain_cnt;

    // ---- 下一状态 (组合逻辑) ----
    wire [2:0] nxt_state;
    assign nxt_state = (state == IDLE    && start_tile)                   ? PRELOAD :
                       (state == IDLE    && !start_tile)                  ? IDLE    :
                       (state == PRELOAD)                                 ? FEED0   :
                       (state == FEED0)                                   ? FEED1   :
                       (state == FEED1)                                   ? FEED2   :
                       (state == FEED2)                                   ? DRAIN   :
                       (state == DRAIN   && (arr_any_finished || drain_cnt > 8'd60)) ? DONE :
                       (state == DRAIN)                                   ? DRAIN   :
                       (state == DONE)                                    ? IDLE    : IDLE;

    // ========================================================================
    // ifmap行解包 → 6个数据切片
    // ========================================================================
    wire [IN_WIDTH-1:0] col [0:17];
    assign col[0]  = ifmap_row_padded[0*IN_WIDTH +: IN_WIDTH];
    assign col[1]  = ifmap_row_padded[1*IN_WIDTH +: IN_WIDTH];
    assign col[2]  = ifmap_row_padded[2*IN_WIDTH +: IN_WIDTH];
    assign col[3]  = ifmap_row_padded[3*IN_WIDTH +: IN_WIDTH];
    assign col[4]  = ifmap_row_padded[4*IN_WIDTH +: IN_WIDTH];
    assign col[5]  = ifmap_row_padded[5*IN_WIDTH +: IN_WIDTH];
    assign col[6]  = ifmap_row_padded[6*IN_WIDTH +: IN_WIDTH];
    assign col[7]  = ifmap_row_padded[7*IN_WIDTH +: IN_WIDTH];
    assign col[8]  = ifmap_row_padded[8*IN_WIDTH +: IN_WIDTH];
    assign col[9]  = ifmap_row_padded[9*IN_WIDTH +: IN_WIDTH];
    assign col[10] = ifmap_row_padded[10*IN_WIDTH +: IN_WIDTH];
    assign col[11] = ifmap_row_padded[11*IN_WIDTH +: IN_WIDTH];
    assign col[12] = ifmap_row_padded[12*IN_WIDTH +: IN_WIDTH];
    assign col[13] = ifmap_row_padded[13*IN_WIDTH +: IN_WIDTH];
    assign col[14] = ifmap_row_padded[14*IN_WIDTH +: IN_WIDTH];
    assign col[15] = ifmap_row_padded[15*IN_WIDTH +: IN_WIDTH];
    assign col[16] = ifmap_row_padded[16*IN_WIDTH +: IN_WIDTH];
    assign col[17] = ifmap_row_padded[17*IN_WIDTH +: IN_WIDTH];

    wire [IN_WIDTH*5-1:0] slice0, slice1, slice2, slice3, slice4, slice5;
    assign slice0 = {col[4], col[3], col[2], col[1], col[0]};
    assign slice1 = {col[7], col[6], col[5], col[4], col[3]};
    assign slice2 = {col[10], col[9], col[8], col[7], col[6]};
    assign slice3 = {col[13], col[12], col[11], col[10], col[9]};
    assign slice4 = {col[16], col[15], col[14], col[13], col[12]};
    assign slice5 = {col[17], col[16], col[15], col[14], col[13]};

    // ========================================================================
    // 输出寄存器 (case nxt_state, posedge采样)
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            drain_cnt    <= 8'd0;
            start_global <= 1'b0;
            new_in_data  <= 1'b0;
            out_data0 <= 0; out_data1 <= 0; out_data2 <= 0;
            out_data3 <= 0; out_data4 <= 0; out_data5 <= 0;
            out_filter <= 0; out_psum_top <= 0;
            tile_done <= 1'b0;
        end else begin
            state     <= nxt_state;
            tile_done <= 1'b0;
            out_psum_top <= psum_top;

            case (nxt_state)
                IDLE: begin
                    start_global <= 1'b0; new_in_data <= 1'b0;
                end

                PRELOAD: begin
                    // 预加载row0数据, 但不发start (下一拍FEED0时数据已稳定)
                    out_data0 <= slice0; out_data1 <= slice1;
                    out_data2 <= slice2; out_data3 <= slice3;
                    out_data4 <= slice4; out_data5 <= slice5;
                    out_filter <= filter_row0;
                end

                FEED0: begin
                    // start=1, new_in_data=1, row0在总线稳定
                    start_global <= 1'b1; new_in_data <= 1'b1;
                    out_data0 <= slice0; out_data1 <= slice1;
                    out_data2 <= slice2; out_data3 <= slice3;
                    out_data4 <= slice4; out_data5 <= slice5;
                    out_filter <= filter_row0;
                end

                FEED1: begin
                    // start=0, new_in_data保持1, row1→总线
                    start_global <= 1'b0; new_in_data <= 1'b1;
                    out_data0 <= slice0; out_data1 <= slice1;
                    out_data2 <= slice2; out_data3 <= slice3;
                    out_data4 <= slice4; out_data5 <= slice5;
                    out_filter <= filter_row1;
                end

                FEED2: begin
                    // new_in_data保持1, row2→总线
                    new_in_data <= 1'b1;
                    out_data0 <= slice0; out_data1 <= slice1;
                    out_data2 <= slice2; out_data3 <= slice3;
                    out_data4 <= slice4; out_data5 <= slice5;
                    out_filter <= filter_row2;
                end

                DRAIN: begin
                    new_in_data <= 1'b0;  // 停止数据锁存
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
