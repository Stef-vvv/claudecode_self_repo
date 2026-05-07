// ===========================================================================
// PE.v — Row-Stationary Processing Element (综合友好, 匹配 pe.py)
// ===========================================================================
// 对应Python: ed_run/pe.py — PE.process_one()
//
// 状态机 (5周期, 与Python完全一致):
//   IDLE(0): 等待start. start=1时锁存数据并计算第一个点积(iter=0), out_start=1
//   MAC(1) : 3次迭代滑窗点积 — iter=1→out_start=0, iter=2→state→ACC
//   ACC(2) : 累加上游部分和(in_result), finished=1, state→DONE
//   DONE(3) : finished=0, state→IDLE
//
// 关键硬件设计 (匹配Python start拍同时锁存+计算):
//   在IDLE+start=1的同一周期:
//     - data/filt寄存器锁存输入端口值 (使用非阻塞赋值)
//     - dot(offset=0)使用输入端口数据(组合逻辑), 结果写入result_r[0]
//     - 硬件路径: in_data→(组合)mux→3个乘法器→2个加法器→result_r[0]
//   这一拍是可综合的: 组合逻辑在时钟沿前稳定, 寄存器在沿后更新.
//
// 参数: IN_WIDTH=5(实际数据Q8但声明为5), W_WIDTH=8(Q8权重), ACC_WIDTH=16(Q16累加)
// ===========================================================================

`timescale 1ns / 1ps

module PE #(
    parameter IN_WIDTH  = 5,    // 输入数据位宽
    parameter W_WIDTH   = 8,    // 权重位宽
    parameter ACC_WIDTH = 16    // 累加器位宽
) (
    input  wire                          clk,
    input  wire                          rst_n,        // 异步复位, 低有效
    input  wire                          start,        // 启动脉冲 (对应Python: pe.start[0])
    input  wire                          new_in_data,  // 数据有效使能 (对应Python: pe.new_in_data[0])
    input  wire [ IN_WIDTH*5 -1 : 0]     in_data,      // 5个数据值打包 (对应Python: pe.in_data[5])
    input  wire [  W_WIDTH*3 -1 : 0]     in_filter,    // 3个滤波器值打包 (对应Python: pe.in_filter[3])
    input  wire [ ACC_WIDTH*3 -1 : 0]    in_result,    // 3个上游部分和打包 (对应Python: pe.in_result[:3])

    output wire [ ACC_WIDTH*3 -1 : 0]    out_result,   // 3个输出结果打包
    output wire [  W_WIDTH*3 -1 : 0]     out_filter,   // 3个滤波器值打包 (向右邻传递)
    output reg                           out_start,    // 启动传播 (对应Python: pe.out_start[0])
    output reg                           finished      // 计算完成 (对应Python: pe.finished)
);

    // ---- 状态编码 (对应Python: pe.state) ----
    localparam IDLE = 2'd0, MAC = 2'd1, ACC = 2'd2, DONE = 2'd3;

    // ---- 内部寄存器 (对应Python PE的属性) ----
    reg [1:0] state, nxt_state;                     // 状态机
    reg [1:0] iter,  nxt_iter;                      // MAC迭代计数 (0,1,2; 对应Python: pe.iteration)
    reg [IN_WIDTH-1:0]  data_r [0:4];               // 锁存数据 (对应Python: pe.data)
    reg [W_WIDTH-1:0]   filt_r [0:2];               // 锁存滤波器 (对应Python: pe.filter)
    reg [ACC_WIDTH-1:0] result_r [0:2];             // 计算结果 (对应Python: pe.result)
    wire [IN_WIDTH-1:0]  nxt_data [0:4];            // 下一状态数据 (组合逻辑)
    wire [W_WIDTH-1:0]   nxt_filt [0:2];            // 下一状态滤波器 (组合逻辑)
    wire [ACC_WIDTH-1:0] nxt_result [0:2];          // 下一状态结果 (组合逻辑)
    reg                 nxt_finished, nxt_out_start; // 下一状态控制信号

    integer i;  // 循环变量 (综合时展开)

    // ========================================================================
    // 总线解包 (组合逻辑)
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
    // 组合逻辑: 点积计算
    // 对应Python: sum(sliding_window[i] * filter[i] for i in range(3))
    //
    // 在 IDLE+start+new_in_data 时, 使用输入端口数据 (因为寄存器尚未更新)
    // 在其他状态使用寄存器数据
    // ========================================================================
    wire [IN_WIDTH-1:0] dot_d0, dot_d1, dot_d2, dot_d3, dot_d4;
    wire [W_WIDTH-1:0]  dot_f0, dot_f1, dot_f2;

    // 数据源选择: IDLE+start+new_in_data → 输入端口, 否则 → 寄存器
    assign dot_d0 = (state == IDLE && start && new_in_data) ? in_d0 : data_r[0];
    assign dot_d1 = (state == IDLE && start && new_in_data) ? in_d1 : data_r[1];
    assign dot_d2 = (state == IDLE && start && new_in_data) ? in_d2 : data_r[2];
    assign dot_d3 = (state == IDLE && start && new_in_data) ? in_d3 : data_r[3];
    assign dot_d4 = (state == IDLE && start && new_in_data) ? in_d4 : data_r[4];
    // filter在start时无条件使用输入端口 (因为总是锁存)
    assign dot_f0 = (state == IDLE && start) ? in_f0 : filt_r[0];
    assign dot_f1 = (state == IDLE && start) ? in_f1 : filt_r[1];
    assign dot_f2 = (state == IDLE && start) ? in_f2 : filt_r[2];

    // 3个滑窗位置的点积 (组合逻辑, 综合为乘法器+加法器树)
    wire [ACC_WIDTH-1:0] dot0, dot1, dot2;
    assign dot0 = dot_d0*dot_f0 + dot_d1*dot_f1 + dot_d2*dot_f2;  // offset=0
    assign dot1 = dot_d1*dot_f0 + dot_d2*dot_f1 + dot_d3*dot_f2;  // offset=1
    assign dot2 = dot_d2*dot_f0 + dot_d3*dot_f1 + dot_d4*dot_f2;  // offset=2

    // ========================================================================
    // 组合逻辑: 下一状态计算 (对应Python process_one中的nxt_*变量)
    // ========================================================================

    // 下一状态数据寄存器 (对应Python: nxt_data)
    assign nxt_data[0] = (state == IDLE && start && new_in_data) ? in_d0 : data_r[0];
    assign nxt_data[1] = (state == IDLE && start && new_in_data) ? in_d1 : data_r[1];
    assign nxt_data[2] = (state == IDLE && start && new_in_data) ? in_d2 : data_r[2];
    assign nxt_data[3] = (state == IDLE && start && new_in_data) ? in_d3 : data_r[3];
    assign nxt_data[4] = (state == IDLE && start && new_in_data) ? in_d4 : data_r[4];

    // 注意: filter在start时无条件更新 (对应Python: self.filter = self.in_filter.copy() 不在new_in_data判断内)
    assign nxt_filt[0] = (state == IDLE && start) ? in_f0 : filt_r[0];
    assign nxt_filt[1] = (state == IDLE && start) ? in_f1 : filt_r[1];
    assign nxt_filt[2] = (state == IDLE && start) ? in_f2 : filt_r[2];

    // 下一状态结果 (对应Python: nxt_result)
    // result[0]: IDLE+start时=dot0, MAC iter=0时=dot0, ACC时=累加, 否则保持
    assign nxt_result[0] = (state == IDLE && start)        ? dot0 :
                           (state == MAC && iter == 2'd0)  ? dot0 :
                           (state == ACC) ? (result_r[0] + in_r0) : result_r[0];
    assign nxt_result[1] = (state == MAC && iter == 2'd1)  ? dot1 :
                           (state == ACC) ? (result_r[1] + in_r1) : result_r[1];
    assign nxt_result[2] = (state == MAC && iter == 2'd2)  ? dot2 :
                           (state == ACC) ? (result_r[2] + in_r2) : result_r[2];

    // ========================================================================
    // 组合逻辑: 下一状态控制 (对应Python的状态转换)
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
                    nxt_iter      = 2'd1;       // iter0的MAC在本周期完成, iter跳至1
                    nxt_out_start = 1'b1;       // 对应Python: self.out_start[0] = 1
                end
            end

            MAC: begin
                case (iter)
                    2'd0: begin nxt_iter = 2'd1; nxt_out_start = 1'b1; end
                    2'd1: begin nxt_iter = 2'd2; nxt_out_start = 1'b0; end  // 对应Python: if iter==2: out_start=0
                    2'd2: begin nxt_iter = 2'd0; nxt_state = ACC; end         // 对应Python: if iter==3: state=2
                endcase
            end

            ACC: begin
                nxt_finished = 1'b1;             // 对应Python: self.finished = 1
                nxt_state    = DONE;
            end

            DONE: begin
                nxt_state = IDLE;                // 对应Python: self.state = 0
                nxt_iter  = 2'd0;
            end
        endcase
    end

    // ========================================================================
    // 时序逻辑: 寄存器更新 (时钟上升沿)
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            iter      <= 2'd0;
            finished  <= 1'b0;
            out_start <= 1'b0;
            for (i = 0; i < 5; i = i + 1) data_r[i]   <= {IN_WIDTH{1'b0}};
            for (i = 0; i < 3; i = i + 1) filt_r[i]   <= {W_WIDTH{1'b0}};
            for (i = 0; i < 3; i = i + 1) result_r[i] <= {ACC_WIDTH{1'b0}};
        end else begin
            state     <= nxt_state;
            iter      <= nxt_iter;
            finished  <= nxt_finished;
            out_start <= nxt_out_start;
            for (i = 0; i < 5; i = i + 1) data_r[i]   <= nxt_data[i];
            for (i = 0; i < 3; i = i + 1) filt_r[i]   <= nxt_filt[i];
            for (i = 0; i < 3; i = i + 1) result_r[i] <= nxt_result[i];
        end
    end

    // ========================================================================
    // 输出 (组合逻辑直连寄存器)
    // ========================================================================
    assign out_result = {result_r[2], result_r[1], result_r[0]};
    assign out_filter = {filt_r[2],   filt_r[1],   filt_r[0]};

endmodule
