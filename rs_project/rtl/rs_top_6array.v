// ===========================================================================
// rs_top_6array.v — 6阵列RS加速器顶层
// ===========================================================================
// Scheduler_6array + 6×PE_Array + Aggregator_6array
// 对应Python: ed_run/top.py — 6阵列完整系统
// ===========================================================================

`timescale 1ns / 1ps

module rs_top_6array #(
    parameter IN_WIDTH  = 5,
    parameter W_WIDTH   = 8,
    parameter ACC_WIDTH = 16,
    parameter OUT_WIDTH = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start_tile,

    // ifmap行 (18元素: pad+16cols+pad)
    input  wire [ IN_WIDTH*18 -1 : 0]    ifmap_row_padded,
    // 3行滤波器
    input  wire [  W_WIDTH*3 -1 : 0]     filter_row0,
    input  wire [  W_WIDTH*3 -1 : 0]     filter_row1,
    input  wire [  W_WIDTH*3 -1 : 0]     filter_row2,
    input  wire [ ACC_WIDTH*3 -1 : 0]    psum_top,
    input  wire [ ACC_WIDTH*OUT_WIDTH-1:0] prev_partial,

    output wire [ ACC_WIDTH*OUT_WIDTH-1:0] acc_result,
    output wire                           acc_valid,
    output wire                           tile_done
);

    // ---- Scheduler信号 ----
    wire                        sched_start, sched_ni_d;
    wire [IN_WIDTH*5-1:0]       sched_d0, sched_d1, sched_d2, sched_d3, sched_d4, sched_d5;
    wire [W_WIDTH*3-1:0]        sched_filt;
    wire [ACC_WIDTH*3-1:0]      sched_psum;
    wire [ACC_WIDTH*3-1:0]      arr_r0, arr_r1, arr_r2, arr_r3, arr_r4, arr_r5;
    wire                        arr_f0, arr_f1, arr_f2, arr_f3, arr_f4, arr_f5;
    wire                        any_fin;

    // ---- Scheduler ----
    Scheduler_6array #(.IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    u_sched (.clk(clk), .rst_n(rst_n), .start_tile(start_tile),
             .ifmap_row_padded(ifmap_row_padded),
             .filter_row0(filter_row0), .filter_row1(filter_row1), .filter_row2(filter_row2),
             .psum_top(psum_top),
             .start_global(sched_start), .new_in_data(sched_ni_d),
             .out_data0(sched_d0), .out_data1(sched_d1), .out_data2(sched_d2),
             .out_data3(sched_d3), .out_data4(sched_d4), .out_data5(sched_d5),
             .out_filter(sched_filt), .out_psum_top(sched_psum),
             .arr_result0(arr_r0), .arr_result1(arr_r1), .arr_result2(arr_r2),
             .arr_result3(arr_r3), .arr_result4(arr_r4), .arr_result5(arr_r5),
             .arr_finished0(arr_f0), .arr_finished1(arr_f1), .arr_finished2(arr_f2),
             .arr_finished3(arr_f3), .arr_finished4(arr_f4), .arr_finished5(arr_f5),
             .any_finished(any_fin), .tile_done(tile_done));

    // ---- 6×PE_Array ----
    PE_Array #(.N(3), .IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    arr0 (.clk(clk), .rst_n(rst_n), .start_global(sched_start), .new_in_data(sched_ni_d),
          .in_data(sched_d0), .in_filter(sched_filt), .in_psum_top(sched_psum),
          .out_result(arr_r0), .out_finished(arr_f0));

    PE_Array #(.N(3), .IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    arr1 (.clk(clk), .rst_n(rst_n), .start_global(sched_start), .new_in_data(sched_ni_d),
          .in_data(sched_d1), .in_filter(sched_filt), .in_psum_top(sched_psum),
          .out_result(arr_r1), .out_finished(arr_f1));

    PE_Array #(.N(3), .IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    arr2 (.clk(clk), .rst_n(rst_n), .start_global(sched_start), .new_in_data(sched_ni_d),
          .in_data(sched_d2), .in_filter(sched_filt), .in_psum_top(sched_psum),
          .out_result(arr_r2), .out_finished(arr_f2));

    PE_Array #(.N(3), .IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    arr3 (.clk(clk), .rst_n(rst_n), .start_global(sched_start), .new_in_data(sched_ni_d),
          .in_data(sched_d3), .in_filter(sched_filt), .in_psum_top(sched_psum),
          .out_result(arr_r3), .out_finished(arr_f3));

    PE_Array #(.N(3), .IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    arr4 (.clk(clk), .rst_n(rst_n), .start_global(sched_start), .new_in_data(sched_ni_d),
          .in_data(sched_d4), .in_filter(sched_filt), .in_psum_top(sched_psum),
          .out_result(arr_r4), .out_finished(arr_f4));

    PE_Array #(.N(3), .IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    arr5 (.clk(clk), .rst_n(rst_n), .start_global(sched_start), .new_in_data(sched_ni_d),
          .in_data(sched_d5), .in_filter(sched_filt), .in_psum_top(sched_psum),
          .out_result(arr_r5), .out_finished(arr_f5));

    // ---- Aggregator ----
    Aggregator_6array #(.ACC_WIDTH(ACC_WIDTH), .OUT_WIDTH(OUT_WIDTH))
    u_agg (.clk(clk), .rst_n(rst_n), .process_trigger(any_fin),
           .arr0_result(arr_r0), .arr1_result(arr_r1), .arr2_result(arr_r2),
           .arr3_result(arr_r3), .arr4_result(arr_r4), .arr5_result(arr_r5),
           .arr0_finished(arr_f0), .arr1_finished(arr_f1), .arr2_finished(arr_f2),
           .arr3_finished(arr_f3), .arr4_finished(arr_f4), .arr5_finished(arr_f5),
           .prev_partial(prev_partial),
           .acc_result(acc_result), .acc_valid(acc_valid));

endmodule
