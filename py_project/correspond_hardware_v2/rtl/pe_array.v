// ===========================================================================
// PE_Array.v — 3×3 RS PE阵列 (无generate, 纯assign+always+逐实例化)
// ===========================================================================
// 对应Python: pe_array.py — PEArray.process()
// 9个PE全部手动实例化, 全部互连信号逐条assign.
// ===========================================================================

`timescale 1ns / 1ps

module PE_Array #(
    parameter N         = 3,
    parameter IN_WIDTH  = 5,
    parameter W_WIDTH   = 8,
    parameter ACC_WIDTH = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start_global,
    input  wire                          new_in_data,
    input  wire [ IN_WIDTH*5 -1 : 0]     in_data,
    input  wire [  W_WIDTH*3 -1 : 0]     in_filter,
    input  wire [ ACC_WIDTH*3 -1 : 0]    in_psum_top,

    output wire [ ACC_WIDTH*3 -1 : 0]    out_result,
    output wire                          out_finished
);

    // ========================================================================
    // PE互连信号 — 3x3=9个PE, 全部逐一声明
    // ========================================================================
    // 数据总线 (广播, 全部接in_data)
    wire [ IN_WIDTH*5 -1 : 0] data_bus_00, data_bus_01, data_bus_02;
    wire [ IN_WIDTH*5 -1 : 0] data_bus_10, data_bus_11, data_bus_12;
    wire [ IN_WIDTH*5 -1 : 0] data_bus_20, data_bus_21, data_bus_22;

    // 滤波器输入
    wire [ W_WIDTH*3 -1 : 0] filt_in_00, filt_in_01, filt_in_02;
    wire [ W_WIDTH*3 -1 : 0] filt_in_10, filt_in_11, filt_in_12;
    wire [ W_WIDTH*3 -1 : 0] filt_in_20, filt_in_21, filt_in_22;

    // 滤波器输出
    wire [ W_WIDTH*3 -1 : 0] filt_out_00, filt_out_01, filt_out_02;
    wire [ W_WIDTH*3 -1 : 0] filt_out_10, filt_out_11, filt_out_12;
    wire [ W_WIDTH*3 -1 : 0] filt_out_20, filt_out_21, filt_out_22;

    // 部分和输入
    wire [ ACC_WIDTH*3 -1 : 0] psum_in_00, psum_in_01, psum_in_02;
    wire [ ACC_WIDTH*3 -1 : 0] psum_in_10, psum_in_11, psum_in_12;
    wire [ ACC_WIDTH*3 -1 : 0] psum_in_20, psum_in_21, psum_in_22;

    // 部分和输出
    wire [ ACC_WIDTH*3 -1 : 0] psum_out_00, psum_out_01, psum_out_02;
    wire [ ACC_WIDTH*3 -1 : 0] psum_out_10, psum_out_11, psum_out_12;
    wire [ ACC_WIDTH*3 -1 : 0] psum_out_20, psum_out_21, psum_out_22;

    // 启动信号
    wire start_00, start_01, start_02;
    wire start_10, start_11, start_12;
    wire start_20, start_21, start_22;

    // 完成标志
    wire fin_00, fin_01, fin_02;
    wire fin_10, fin_11, fin_12;
    wire fin_20, fin_21, fin_22;

    // out_start
    wire os_00, os_01, os_02;
    wire os_10, os_11, os_12;
    wire os_20, os_21, os_22;

    // ========================================================================
    // 数据广播: 全部9个PE接同一in_data
    // ========================================================================
    assign data_bus_00 = in_data; assign data_bus_01 = in_data; assign data_bus_02 = in_data;
    assign data_bus_10 = in_data; assign data_bus_11 = in_data; assign data_bus_12 = in_data;
    assign data_bus_20 = in_data; assign data_bus_21 = in_data; assign data_bus_22 = in_data;

    // ========================================================================
    // 滤波器连接: 列0=外部, 列1=左邻out, 列2=左邻out
    // ========================================================================
    assign filt_in_00 = in_filter; assign filt_in_01 = filt_out_00; assign filt_in_02 = filt_out_01;
    assign filt_in_10 = in_filter; assign filt_in_11 = filt_out_10; assign filt_in_12 = filt_out_11;
    assign filt_in_20 = in_filter; assign filt_in_21 = filt_out_20; assign filt_in_22 = filt_out_21;

    // ========================================================================
    // 部分和连接: 行0=外部, 行1=上邻out, 行2=上邻out
    // ========================================================================
    assign psum_in_00 = in_psum_top; assign psum_in_01 = in_psum_top; assign psum_in_02 = in_psum_top;
    assign psum_in_10 = psum_out_00; assign psum_in_11 = psum_out_01; assign psum_in_12 = psum_out_02;
    assign psum_in_20 = psum_out_10; assign psum_in_21 = psum_out_11; assign psum_in_22 = psum_out_12;

    // ========================================================================
    // 启动信号: 对角线传播 (左os | 上os)
    // ========================================================================
    assign start_00 = start_global;
    assign start_01 = os_00;                                        // 第0行, 来自左
    assign start_02 = os_01;                                        // 第0行, 来自左
    assign start_10 = os_00;                                        // 第0列, 来自上
    assign start_11 = os_01 | os_10;                                // 来自左或上
    assign start_12 = os_02 | os_11;                                // 来自左或上
    assign start_20 = os_10;                                        // 第0列, 来自上
    assign start_21 = os_11 | os_20;                                // 来自左或上
    assign start_22 = os_12 | os_21;                                // 来自左或上

    // ========================================================================
    // PE实例化 (9个, 逐一手动实例化)
    // ========================================================================
    PE #(.IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    pe_00 (.clk(clk), .rst_n(rst_n), .start(start_00), .new_in_data(new_in_data),
           .in_data(data_bus_00), .in_filter(filt_in_00), .in_result(psum_in_00),
           .out_result(psum_out_00), .out_filter(filt_out_00),
           .out_start(os_00), .finished(fin_00));

    PE #(.IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    pe_01 (.clk(clk), .rst_n(rst_n), .start(start_01), .new_in_data(new_in_data),
           .in_data(data_bus_01), .in_filter(filt_in_01), .in_result(psum_in_01),
           .out_result(psum_out_01), .out_filter(filt_out_01),
           .out_start(os_01), .finished(fin_01));

    PE #(.IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    pe_02 (.clk(clk), .rst_n(rst_n), .start(start_02), .new_in_data(new_in_data),
           .in_data(data_bus_02), .in_filter(filt_in_02), .in_result(psum_in_02),
           .out_result(psum_out_02), .out_filter(filt_out_02),
           .out_start(os_02), .finished(fin_02));

    PE #(.IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    pe_10 (.clk(clk), .rst_n(rst_n), .start(start_10), .new_in_data(new_in_data),
           .in_data(data_bus_10), .in_filter(filt_in_10), .in_result(psum_in_10),
           .out_result(psum_out_10), .out_filter(filt_out_10),
           .out_start(os_10), .finished(fin_10));

    PE #(.IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    pe_11 (.clk(clk), .rst_n(rst_n), .start(start_11), .new_in_data(new_in_data),
           .in_data(data_bus_11), .in_filter(filt_in_11), .in_result(psum_in_11),
           .out_result(psum_out_11), .out_filter(filt_out_11),
           .out_start(os_11), .finished(fin_11));

    PE #(.IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    pe_12 (.clk(clk), .rst_n(rst_n), .start(start_12), .new_in_data(new_in_data),
           .in_data(data_bus_12), .in_filter(filt_in_12), .in_result(psum_in_12),
           .out_result(psum_out_12), .out_filter(filt_out_12),
           .out_start(os_12), .finished(fin_12));

    PE #(.IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    pe_20 (.clk(clk), .rst_n(rst_n), .start(start_20), .new_in_data(new_in_data),
           .in_data(data_bus_20), .in_filter(filt_in_20), .in_result(psum_in_20),
           .out_result(psum_out_20), .out_filter(filt_out_20),
           .out_start(os_20), .finished(fin_20));

    PE #(.IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    pe_21 (.clk(clk), .rst_n(rst_n), .start(start_21), .new_in_data(new_in_data),
           .in_data(data_bus_21), .in_filter(filt_in_21), .in_result(psum_in_21),
           .out_result(psum_out_21), .out_filter(filt_out_21),
           .out_start(os_21), .finished(fin_21));

    PE #(.IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
    pe_22 (.clk(clk), .rst_n(rst_n), .start(start_22), .new_in_data(new_in_data),
           .in_data(data_bus_22), .in_filter(filt_in_22), .in_result(psum_in_22),
           .out_result(psum_out_22), .out_filter(filt_out_22),
           .out_start(os_22), .finished(fin_22));

    // ========================================================================
    // 阵列输出: 最底行优先列0, 否则列1, 否则列2
    // ========================================================================
    assign out_result = fin_20 ? psum_out_20 :
                        fin_21 ? psum_out_21 :
                        fin_22 ? psum_out_22 :
                        {ACC_WIDTH*3{1'b0}};
    assign out_finished = fin_20 | fin_21 | fin_22;

endmodule
