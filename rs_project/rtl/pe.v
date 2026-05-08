// ===========================================================================
// PE.v — Row-Stationary Processing Element (无for/generate, 纯assign+always)
// ===========================================================================
// 对应Python: pe.py — PE.process_one()
// 5拍状态机: IDLE→MAC(iter0,1,2)→ACC→DONE→IDLE
// 全部寄存器位展开, 无循环语句, 无generate块, 无SystemVerilog特性.
// ===========================================================================

`timescale 1ns / 1ps

module PE #(
    parameter IN_WIDTH  = 5,
    parameter W_WIDTH   = 8,
    parameter ACC_WIDTH = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start,
    input  wire                          new_in_data,
    input  wire [ IN_WIDTH*5 -1 : 0]     in_data,
    input  wire [  W_WIDTH*3 -1 : 0]     in_filter,
    input  wire [ ACC_WIDTH*3 -1 : 0]    in_result,

    output wire [ ACC_WIDTH*3 -1 : 0]    out_result,
    output wire [  W_WIDTH*3 -1 : 0]     out_filter,
    output reg                           out_start,
    output reg                           finished
);

    localparam IDLE = 2'd0, MAC = 2'd1, ACC = 2'd2, DONE = 2'd3;

    // ---- 状态寄存器 ----
    reg [1:0] state, nxt_state;
    reg [1:0] iter,  nxt_iter;

    // ---- 数据寄存器 (5个, 逐一声明) ----
    reg [IN_WIDTH-1:0] data_r0, data_r1, data_r2, data_r3, data_r4;
    wire [IN_WIDTH-1:0] nxt_data0, nxt_data1, nxt_data2, nxt_data3, nxt_data4;

    // ---- 滤波器寄存器 (3个, 逐一声明) ----
    reg [W_WIDTH-1:0]  filt_r0, filt_r1, filt_r2;
    wire [W_WIDTH-1:0]  nxt_filt0, nxt_filt1, nxt_filt2;

    // ---- 结果寄存器 (3个, 逐一声明) ----
    reg [ACC_WIDTH-1:0] result_r0, result_r1, result_r2;
    wire [ACC_WIDTH-1:0] nxt_result0, nxt_result1, nxt_result2;

    // ---- 控制信号下一状态 ----
    reg nxt_finished, nxt_out_start;

    // ========================================================================
    // 总线解包 (组合逻辑, 逐位展开)
    // ========================================================================
    wire [IN_WIDTH-1:0]  in_d0, in_d1, in_d2, in_d3, in_d4;
    wire [W_WIDTH-1:0]   in_f0, in_f1, in_f2;
    wire [ACC_WIDTH-1:0] in_r0, in_r1, in_r2;

    assign in_d0 = in_data[0*IN_WIDTH +: IN_WIDTH];
    assign in_d1 = in_data[1*IN_WIDTH +: IN_WIDTH];
    assign in_d2 = in_data[2*IN_WIDTH +: IN_WIDTH];
    assign in_d3 = in_data[3*IN_WIDTH +: IN_WIDTH];
    assign in_d4 = in_data[4*IN_WIDTH +: IN_WIDTH];
    assign in_f0 = in_filter[0*W_WIDTH +: W_WIDTH];
    assign in_f1 = in_filter[1*W_WIDTH +: W_WIDTH];
    assign in_f2 = in_filter[2*W_WIDTH +: W_WIDTH];
    assign in_r0 = in_result[0*ACC_WIDTH +: ACC_WIDTH];
    assign in_r1 = in_result[1*ACC_WIDTH +: ACC_WIDTH];
    assign in_r2 = in_result[2*ACC_WIDTH +: ACC_WIDTH];

    // ========================================================================
    // 点积数据源选择 (IDLE+start时用输入端口, 否则用寄存器)
    // ========================================================================
    wire [IN_WIDTH-1:0] dot_d0, dot_d1, dot_d2, dot_d3, dot_d4;
    wire [W_WIDTH-1:0]  dot_f0, dot_f1, dot_f2;

    assign dot_d0 = (state == IDLE && start && new_in_data) ? in_d0 : data_r0;
    assign dot_d1 = (state == IDLE && start && new_in_data) ? in_d1 : data_r1;
    assign dot_d2 = (state == IDLE && start && new_in_data) ? in_d2 : data_r2;
    assign dot_d3 = (state == IDLE && start && new_in_data) ? in_d3 : data_r3;
    assign dot_d4 = (state == IDLE && start && new_in_data) ? in_d4 : data_r4;
    assign dot_f0 = (state == IDLE && start) ? in_f0 : filt_r0;
    assign dot_f1 = (state == IDLE && start) ? in_f1 : filt_r1;
    assign dot_f2 = (state == IDLE && start) ? in_f2 : filt_r2;

    // ---- 3个滑窗点积 (组合: 乘法器+加法器树) ----
    wire [ACC_WIDTH-1:0] dot0, dot1, dot2;
    assign dot0 = dot_d0*dot_f0 + dot_d1*dot_f1 + dot_d2*dot_f2;
    assign dot1 = dot_d1*dot_f0 + dot_d2*dot_f1 + dot_d3*dot_f2;
    assign dot2 = dot_d2*dot_f0 + dot_d3*dot_f1 + dot_d4*dot_f2;

    // ========================================================================
    // 下一状态 — 数据寄存器 (逐位assign)
    // ========================================================================
    assign nxt_data0 = (state == IDLE && start && new_in_data) ? in_d0 : data_r0;
    assign nxt_data1 = (state == IDLE && start && new_in_data) ? in_d1 : data_r1;
    assign nxt_data2 = (state == IDLE && start && new_in_data) ? in_d2 : data_r2;
    assign nxt_data3 = (state == IDLE && start && new_in_data) ? in_d3 : data_r3;
    assign nxt_data4 = (state == IDLE && start && new_in_data) ? in_d4 : data_r4;

    // ---- 下一状态 — 滤波器寄存器 (start时无条件更新) ----
    assign nxt_filt0 = (state == IDLE && start) ? in_f0 : filt_r0;
    assign nxt_filt1 = (state == IDLE && start) ? in_f1 : filt_r1;
    assign nxt_filt2 = (state == IDLE && start) ? in_f2 : filt_r2;

    // ---- 下一状态 — 结果寄存器 ----
    assign nxt_result0 = (state == IDLE && start)        ? dot0 :
                         (state == MAC && iter == 2'd0)  ? dot0 :
                         (state == ACC) ? (result_r0 + in_r0) : result_r0;
    assign nxt_result1 = (state == MAC && iter == 2'd1)  ? dot1 :
                         (state == ACC) ? (result_r1 + in_r1) : result_r1;
    assign nxt_result2 = (state == MAC && iter == 2'd2)  ? dot2 :
                         (state == ACC) ? (result_r2 + in_r2) : result_r2;

    // ========================================================================
    // 组合逻辑: 下一状态控制
    // ========================================================================
    always @(*) begin
        nxt_state    = state;
        nxt_iter     = iter;
        nxt_finished = 1'b0;
        nxt_out_start = 1'b0;

        case (state)
            IDLE: begin
                if (start) begin
                    nxt_state     = MAC;
                    nxt_iter      = 2'd1;       // iter0的MAC本周期完成
                    nxt_out_start = 1'b1;
                end
            end
            MAC: begin
                case (iter)
                    2'd0: begin nxt_iter = 2'd1; nxt_out_start = 1'b1; end
                    2'd1: begin nxt_iter = 2'd2; nxt_out_start = 1'b0; end
                    2'd2: begin nxt_iter = 2'd0; nxt_state = ACC; end
                endcase
            end
            ACC: begin
                nxt_finished = 1'b1;
                nxt_state    = DONE;
            end
            DONE: begin
                nxt_state = IDLE;
                nxt_iter  = 2'd0;
            end
        endcase
    end

    // ========================================================================
    // 时序逻辑: 寄存器更新 (逐寄存器赋值, 无for)
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            iter      <= 2'd0;
            finished  <= 1'b0;
            out_start <= 1'b0;
            data_r0 <= {IN_WIDTH{1'b0}}; data_r1 <= {IN_WIDTH{1'b0}};
            data_r2 <= {IN_WIDTH{1'b0}}; data_r3 <= {IN_WIDTH{1'b0}};
            data_r4 <= {IN_WIDTH{1'b0}};
            filt_r0 <= {W_WIDTH{1'b0}};  filt_r1 <= {W_WIDTH{1'b0}};
            filt_r2 <= {W_WIDTH{1'b0}};
            result_r0 <= {ACC_WIDTH{1'b0}};
            result_r1 <= {ACC_WIDTH{1'b0}};
            result_r2 <= {ACC_WIDTH{1'b0}};
        end else begin
            state     <= nxt_state;
            iter      <= nxt_iter;
            finished  <= nxt_finished;
            out_start <= nxt_out_start;
            data_r0 <= nxt_data0; data_r1 <= nxt_data1;
            data_r2 <= nxt_data2; data_r3 <= nxt_data3;
            data_r4 <= nxt_data4;
            filt_r0 <= nxt_filt0; filt_r1 <= nxt_filt1;
            filt_r2 <= nxt_filt2;
            result_r0 <= nxt_result0;
            result_r1 <= nxt_result1;
            result_r2 <= nxt_result2;
        end
    end

    // ---- 输出 ----
    assign out_result = {result_r2, result_r1, result_r0};
    assign out_filter = {filt_r2,   filt_r1,   filt_r0};

endmodule
