// ===========================================================================
// rs_top.v — RS加速器顶层 (Scheduler + PE_Array + Aggregator)
// ===========================================================================
// 对应Python: ed_run/top.py — Top.run()
//
// 单tile处理流程:
//   1. 外部加载ifmap_row[0:2] + filter_row[0:2] + psum_top
//   2. 发start_tile脉冲
//   3. Scheduler控制3拍RS时序→PE_Array计算→Aggregator累加
//   4. 等待tile_done, 读取acc_result
//
// 完整conv2: 外部循环遍历ic/tile/oc, 每次调用一个tile.
// ===========================================================================

`timescale 1ns / 1ps

module rs_top #(
    parameter IN_WIDTH  = 5,
    parameter W_WIDTH   = 8,
    parameter ACC_WIDTH = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start_tile,

    // Tile数据输入
    input  wire [ IN_WIDTH*5 -1 : 0]     ifmap_row0,
    input  wire [ IN_WIDTH*5 -1 : 0]     ifmap_row1,
    input  wire [ IN_WIDTH*5 -1 : 0]     ifmap_row2,
    input  wire [  W_WIDTH*3 -1 : 0]     filter_row0,
    input  wire [  W_WIDTH*3 -1 : 0]     filter_row1,
    input  wire [  W_WIDTH*3 -1 : 0]     filter_row2,
    input  wire [ ACC_WIDTH*3 -1 : 0]    psum_top,
    input  wire [ ACC_WIDTH*3 -1 : 0]    prev_partial,

    // 输出
    output wire [ ACC_WIDTH*3 -1 : 0]    acc_result,
    output wire                          acc_valid,
    output wire                          tile_done
);

    // ---- 互连信号 ----
    wire                        sched_start_global;
    wire                        sched_new_in_data;
    wire [ IN_WIDTH*5 -1 : 0]   sched_data;
    wire [  W_WIDTH*3 -1 : 0]   sched_filter;
    wire [ ACC_WIDTH*3 -1 : 0]  sched_psum;
    wire [ ACC_WIDTH*3 -1 : 0]  array_result;
    wire                        array_finished;
    wire [ ACC_WIDTH*3 -1 : 0]  sched_tile_result;
    wire                        sched_tile_done;

    // ---- Scheduler ----
    Scheduler #(
        .IN_WIDTH (IN_WIDTH),
        .W_WIDTH  (W_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_scheduler (
        .clk           (clk),
        .rst_n         (rst_n),
        .start_tile    (start_tile),
        .ifmap_row0    (ifmap_row0),
        .ifmap_row1    (ifmap_row1),
        .ifmap_row2    (ifmap_row2),
        .filter_row0   (filter_row0),
        .filter_row1   (filter_row1),
        .filter_row2   (filter_row2),
        .psum_top      (psum_top),
        .start_global  (sched_start_global),
        .new_in_data   (sched_new_in_data),
        .out_data      (sched_data),
        .out_filter    (sched_filter),
        .out_psum_top  (sched_psum),
        .array_result  (array_result),
        .array_finished(array_finished),
        .tile_result   (sched_tile_result),
        .tile_done     (sched_tile_done)
    );

    // ---- PE Array ----
    PE_Array #(
        .N         (3),
        .IN_WIDTH  (IN_WIDTH),
        .W_WIDTH   (W_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) u_pe_array (
        .clk          (clk),
        .rst_n        (rst_n),
        .start_global (sched_start_global),
        .new_in_data  (sched_new_in_data),
        .in_data      (sched_data),
        .in_filter    (sched_filter),
        .in_psum_top  (sched_psum),
        .out_result   (array_result),
        .out_finished (array_finished)
    );

    // ---- Aggregator ----
    Aggregator #(
        .ACC_WIDTH (ACC_WIDTH)
    ) u_aggregator (
        .clk            (clk),
        .rst_n          (rst_n),
        .array_result   (array_result),
        .array_finished (array_finished),
        .prev_partial   (prev_partial),
        .acc_result     (acc_result),
        .acc_valid      (acc_valid)
    );

    assign tile_done = sched_tile_done;

endmodule
