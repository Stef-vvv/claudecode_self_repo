// =============================================================================
// 模块名称: psum_index_generator (部分和索引生成器)
// 功能描述: 生成部分和(Psum)存储器的4维索引, 用于读写部分和数据。
//           同时被ipsum_noc_controller(输入通路)和opsum_noc_controller(输出通路)复用。
// 数据结构: 4维数组 [n(批)][m(输出通道)][e(高度)][F(宽度)]
// 迭代逻辑:
//   OUTER_LOOP: for e(行) for t(通道组)
//     每个OUTER_LOOP跳回INNER_LOOP, INNER_LOOP执行i=4次
//   INNER_LOOP: for n(批) for F(列) for p(通道分块)
//     lock机制与filter_index_generator相同
//   DONE: 更新m(输出通道基数), m += p*t (跨通道组步进)
// 索引输出:
//   psum_index = n_crnt (批索引)
//   channel_index = m_crnt + p_crnt + t_crnt * p (输出通道索引)
//   row_index = e_crnt (行)
//   col_index = F_crnt (列)
// =============================================================================

module psum_index_generator
#(
    // 特征图宽度位宽
    parameter F_WIDTH = 6,
    // 输出通道总数位宽
    parameter m_WIDTH = 8,
    // 批大小位宽
    parameter n_WIDTH = 3,
    // 特征图高度位宽
    parameter e_WIDTH = 8,
    // 输出通道分块位宽
    parameter p_WIDTH = 5,
    // 输出通道组数位宽
    parameter t_WIDTH = 3,
    // 内循环计数器位宽
    parameter i_WIDTH = 3
) (
    input clk,
    input reset,
    input start,
    input await,           // 反压信号

    output reg busy,
    output reg done,

    // 各维度最大尺寸
    input [F_WIDTH - 1:0] F,    // 特征图宽度
    input [m_WIDTH - 1:0] m,    // 输出通道总数
    input [n_WIDTH - 1:0] n,    // 批大小
    input [e_WIDTH - 1:0] e,    // 特征图高度
    input [p_WIDTH - 1:0] p,    // 输出通道分块
    input [t_WIDTH - 1:0] t,    // 输出通道组数

    // psum_index: 批索引 (n维度)
    output reg [n_WIDTH - 1:0] psum_index,
    // channel_index: m + p + t*p (输出通道索引)
    output reg [m_WIDTH - 1:0] channel_index,
    // row_index: 行索引 (e维度)
    output reg [e_WIDTH - 1:0] row_index,
    // col_index: 列索引 (F维度)
    output reg [F_WIDTH - 1:0] col_index
);

    // 内层循环固定4次
    localparam i = 4;

    // FSM: IDLE -> INNER_LOOP -> OUTER_LOOP -> DONE
    typedef enum {IDLE, OUTER_LOOP, INNER_LOOP, DONE} state_type;
    state_type state_nxt, state_crnt;

    // 各维度计数器
    logic [F_WIDTH - 1:0] F_nxt, F_crnt;
    logic [m_WIDTH - 1:0] m_nxt, m_crnt;
    logic [n_WIDTH - 1:0] n_nxt, n_crnt;
    logic [e_WIDTH - 1:0] e_nxt, e_crnt;
    logic [p_WIDTH - 1:0] p_nxt, p_crnt;
    logic [t_WIDTH - 1:0] t_nxt, t_crnt;
    logic [i_WIDTH - 1:0] i_nxt, i_crnt;

    // 保存寄存器 (lock机制)
    logic [F_WIDTH - 1:0] F_reg_nxt, F_reg_crnt;
    logic [n_WIDTH - 1:0] n_reg_nxt, n_reg_crnt;
    logic [p_WIDTH - 1:0] p_reg_nxt, p_reg_crnt;

    logic lock_nxt, lock_crnt;

    // ---- 时序逻辑 ----
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            F_crnt <= 0;
            m_crnt <= 0;
            n_crnt <= 0;
            e_crnt <= 0;
            p_crnt <= 0;
            t_crnt <= 0;
            i_crnt <= 0;

            F_reg_crnt <= 0;
            n_reg_crnt <= 0;
            p_reg_crnt <= 0;

            lock_crnt <= 1;
        end else begin
            state_crnt <= state_nxt;
            F_crnt <= F_nxt;
            m_crnt <= m_nxt;
            n_crnt <= n_nxt;
            e_crnt <= e_nxt;
            p_crnt <= p_nxt;
            t_crnt <= t_nxt;
            i_crnt <= i_nxt;

            F_reg_crnt <= F_reg_nxt;
            n_reg_crnt <= n_reg_nxt;
            p_reg_crnt <= p_reg_nxt;

            lock_crnt <= lock_nxt;
        end
    end

    // ---- 组合逻辑: FSM ----
    always @(*) begin
        // 默认赋值
        busy = 1'b0;
        done = 1'b0;
        state_nxt = state_crnt;
        F_nxt = F_crnt;
        m_nxt = m_crnt;
        n_nxt = n_crnt;
        e_nxt = e_crnt;
        p_nxt = p_crnt;
        t_nxt = t_crnt;
        i_nxt = i_crnt;

        F_reg_nxt = F_reg_crnt;
        n_reg_nxt = n_reg_crnt;
        p_reg_nxt = p_reg_crnt;

        lock_nxt = lock_crnt;
        case(state_crnt)
            // IDLE: 等待启动
            IDLE:
            begin
                if (start) begin
                    state_nxt = INNER_LOOP;
                end
            end

            // OUTER_LOOP: 外层循环 (e维度, t维度)
            // for e(行) for t(通道组)
            OUTER_LOOP:
            begin
                lock_nxt = 1'b1;                    // 设置lock
                if (t_crnt == t - 1) begin          // t(通道组)到头?
                    if (e_crnt == e - 1) begin      // e(行)到头?
                        e_nxt = 0;
                        t_nxt = 0;
                        if (!lock_crnt) begin
                            state_nxt = DONE;       // 内层也完成
                        end else begin
                            state_nxt = INNER_LOOP;
                        end
                        // 保存入口值
                        F_reg_nxt = F_crnt;
                        n_reg_nxt = n_crnt;
                        p_reg_nxt = p_crnt;
                    end else begin
                        // e递增, t归零
                        e_nxt = e_crnt + 1;
                        t_nxt = 0;
                        state_nxt = INNER_LOOP;
                        // 恢复锁存值
                        F_nxt = F_reg_crnt;
                        n_nxt = n_reg_crnt;
                        p_nxt = p_reg_crnt;
                    end
                end else begin
                    // t递增
                    t_nxt = t_crnt + 1;
                    state_nxt = INNER_LOOP;
                    F_nxt = F_reg_crnt;
                    n_nxt = n_reg_crnt;
                    p_nxt = p_reg_crnt;
                end
            end

            // INNER_LOOP: 内层循环 (p, F, n维度)
            // for n(批) for F(列) for p(通道分块)
            // 每种组合迭代 i=4 次
            INNER_LOOP:
            begin
                if (!await) begin
                    busy = 1'b1;
                    if (i_crnt == i - 1) begin
                        i_nxt = 0;
                        state_nxt = OUTER_LOOP;
                    end else begin
                        i_nxt = i_crnt + 1;
                    end

                    if (lock_crnt) begin
                        if (p_crnt == p - 1) begin       // p到头
                            p_nxt = 0;
                            if (F_crnt == F - 1) begin   // F到头
                                F_nxt = 0;
                                if (n_crnt == n - 1) begin  // n到头
                                    lock_nxt = 1'b0;     // 释放lock
                                    n_nxt = 0;
                                end else begin
                                    n_nxt = n_crnt + 1;
                                end
                            end else begin
                                F_nxt = F_crnt + 1;
                            end
                        end else begin
                            p_nxt = p_crnt + 1;
                        end
                     end
                end
            end

            // DONE: 完成一轮迭代, 更新m基数
            DONE:
            begin
                done = 1'b1;
                // 更新m: 跨通道组步进
                // m = m_crnt + p*t: 跳过当前处理的所有通道
                if (m_crnt + (p * t) == m) begin
                    m_nxt = 0;               // 所有通道完成, 归零
                end else begin
                    m_nxt = m_crnt + (p * t); // 步进到下一组通道
                end
                state_nxt = IDLE;
            end
            default: state_nxt = IDLE;
        endcase
    end

    // ---- 索引输出 ----
    // psum_index = n_crnt: 批索引
    // channel_index = m_crnt + p_crnt + (t_crnt * p): 输出通道索引
    //   m_crnt: 通道组基数
    //   p_crnt: 组内偏移
    //   t_crnt * p: 组内行偏移
    always @(*) begin
        psum_index    = n_crnt;
        channel_index = m_crnt + p_crnt + (t_crnt * p);
        row_index     = e_crnt;
        col_index     = F_crnt;
    end

endmodule
