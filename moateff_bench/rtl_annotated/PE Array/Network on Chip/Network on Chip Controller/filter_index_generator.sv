// =============================================================================
// 模块名称: filter_index_generator (滤波器索引生成器)
// 功能描述: 生成滤波器(Weight)存储器的5维索引, 驱动从全局缓冲区读取滤波器数据。
//           实现 nested-loop 的迭代逻辑:
//             for R (滤波器行)    -> row_index
//               for S (滤波器列)  -> col_index
//                 for q (输入通道分块) for r (通道复用)
//                   for p (输出通道分块) for t (通道复用)
//                     每个内层循环迭代 i=4 次 (localparam i=4, 每周期读4个数据)
// 数据流角色: filter_noc_controller 的地址生成引擎,
//           输出四个维度索引供 mapper 计算线性地址:
//           filter_index(p,t), channel_index(q,r), row_index(R), col_index(S)
// FSM状态: IDLE -> INNER_LOOP(4次) -> OUTER_LOOP(更新t/r/R) -> DONE
// Lock机制: OUTER_LOOP开始时锁存S,p,q的入口值, 内层循环从锁存值开始迭代
// =============================================================================

module filter_index_generator
#(
    // 滤波器高度维度 R 位宽 (如 R=3, 3x3卷积核高度)
    parameter R_WIDTH = 4,
    // 滤波器宽度维度 S 位宽 (如 S=3, 3x3卷积核宽度)
    parameter S_WIDTH = 6,
    // 输出通道分块维度 p 位宽 (p个输出通道一批)
    parameter p_WIDTH = 5,
    // 输入通道分块维度 q 位宽 (q个输入通道一批)
    parameter q_WIDTH = 3,
    // 输入通道复用维度 r 位宽 (r组q通道)
    parameter r_WIDTH = 2,
    // 输出通道复用维度 t 位宽 (t组p通道)
    parameter t_WIDTH = 3,
    // 内循环计数器位宽 (localparam i=4 -> 需要3位)
    parameter i_WIDTH = 3
) (
    input clk,
    input reset,
    // 启动信号
    input start,
    // 反压信号: 下游FIFO满时暂停索引更新
    input await,

    // 忙标志: 为1时表示正在生成索引, 同时驱动filter_noc_controller的re_from_glb
    output reg busy,
    // 完成标志: 一轮迭代完成
    output reg done,

    // 各维度最大尺寸输入
    input [R_WIDTH - 1:0] R,    // 滤波器高度(如3)
    input [S_WIDTH - 1:0] S,    // 滤波器宽度(如3)
    input [p_WIDTH - 1:0] p,    // 输出通道分块大小
    input [q_WIDTH - 1:0] q,    // 输入通道分块大小
    input [r_WIDTH - 1:0] r,    // 输入通道组数
    input [t_WIDTH - 1:0] t,    // 输出通道组数

    // 滤波器索引: p_idx + t_idx * p (在p*t平面内的线性位置)
    output reg [p_WIDTH + t_WIDTH - 1:0] filter_index,
    // 通道索引: q_idx + r_idx * q (在q*r平面内的线性位置)
    output reg [q_WIDTH + r_WIDTH - 1:0] channel_index,
    // 行索引: 滤波器内行号(0~R-1)
    output reg [R_WIDTH - 1:0] row_index,
    // 列索引: 滤波器内列号(0~S-1)
    output reg [S_WIDTH - 1:0] col_index
);

    // 内层循环固定4次 (每个INNER_LOOP状态停留4个周期, 每周期读一个数据)
    localparam i = 4;

    // FSM状态定义
    // IDLE:         等待start信号
    // OUTER_LOOP:   更新外层循环变量(t, r, R) - 滤波器空间维度迭代
    // INNER_LOOP:   内层4次迭代, 更新内层循环变量(p, q, S) - 通道维度迭代
    // DONE:         输出done脉冲, 返回IDLE
    typedef enum {IDLE, OUTER_LOOP, INNER_LOOP, DONE} state_type;
    state_type state_nxt, state_crnt;

    // 各维度当前计数器 (crnt=当前值, nxt=下一值)
    logic [S_WIDTH - 1:0] S_nxt, S_crnt;   // S: 滤波器列
    logic [R_WIDTH - 1:0] R_nxt, R_crnt;   // R: 滤波器行
    logic [p_WIDTH - 1:0] p_nxt, p_crnt;   // p: 输出通道组内偏移
    logic [q_WIDTH - 1:0] q_nxt, q_crnt;   // q: 输入通道组内偏移
    logic [r_WIDTH - 1:0] r_nxt, r_crnt;   // r: 输入通道组号
    logic [t_WIDTH - 1:0] t_nxt, t_crnt;   // t: 输出通道组号
    logic [i_WIDTH - 1:0] i_nxt, i_crnt;   // i: 内循环4次计数器

    // 外部循环入口保存寄存器: lock时保存进入OUTER_LOOP时的初始值
    // lock机制: OUTER_LOOP开始时锁存S,p,q的入口值, 内层循环结束后恢复
    logic [S_WIDTH - 1:0] S_reg_nxt, S_reg_crnt;
    logic [p_WIDTH - 1:0] p_reg_nxt, p_reg_crnt;
    logic [q_WIDTH - 1:0] q_reg_nxt, q_reg_crnt;

    // lock标志: 1=内层循环使用锁存值, 0=内层循环使用当前值
    logic lock_nxt, lock_crnt;

    // ---- 时序逻辑: negedge clk触发 (与数据读出同步) ----
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            S_crnt <= 0;
            R_crnt <= 0;
            p_crnt <= 0;
            q_crnt <= 0;
            r_crnt <= 0;
            t_crnt <= 0;
            i_crnt <= 0;

            S_reg_crnt <= 0;
            p_reg_crnt <= 0;
            q_reg_crnt <= 0;

            lock_crnt <= 1;     // 复位时锁住, 从锁存值开始
        end else begin
            state_crnt <= state_nxt;
            S_crnt <= S_nxt;
            R_crnt <= R_nxt;
            p_crnt <= p_nxt;
            q_crnt <= q_nxt;
            r_crnt <= r_nxt;
            t_crnt <= t_nxt;
            i_crnt <= i_nxt;

            S_reg_crnt <= S_reg_nxt;
            p_reg_crnt <= p_reg_nxt;
            q_reg_crnt <= q_reg_nxt;

            lock_crnt <= lock_nxt;
        end
    end

    // ---- 组合逻辑: FSM状态转移 ----
    always @(*) begin
        // 默认赋值: 保持当前值
        busy = 1'b0;
        done = 1'b0;
        state_nxt = state_crnt;
        S_nxt = S_crnt;
        R_nxt = R_crnt;
        p_nxt = p_crnt;
        q_nxt = q_crnt;
        r_nxt = r_crnt;
        t_nxt = t_crnt;
        i_nxt = i_crnt;

        S_reg_nxt = S_reg_crnt;
        p_reg_nxt = p_reg_crnt;
        q_reg_nxt = q_reg_crnt;

        lock_nxt = lock_crnt;
        case(state_crnt)
            // ---- IDLE: 等待start ----
            IDLE:
            begin
                if (start) begin
                    // 直接跳到INNER_LOOP (跳过第一次OUTER_LOOP)
                    state_nxt = INNER_LOOP;
                end
            end

            // ---- OUTER_LOOP: 外层循环 (滤波器空间维度) ----
            // 嵌套: for R(行) for r(输入通道组) for t(输出通道组)
            OUTER_LOOP:
            begin
                lock_nxt = 1'b1;                // 每次进入OUTER_LOOP都设置lock
                if (t_crnt == t - 1) begin      // t(输出通道组)到头?
                    if (r_crnt == r - 1) begin  // r(输入通道组)到头?
                        if (R_crnt == R - 1) begin  // R(滤波器行)到头?
                            R_nxt = 0;
                            r_nxt = 0;
                            t_nxt = 0;
                            if (!lock_crnt) begin
                                // lock=0: 内层循环全部完成, 进入DONE
                                state_nxt = DONE;
                            end else begin
                                // lock=1: 内层还有未完成迭代, 继续INNER_LOOP
                                state_nxt = INNER_LOOP;
                            end
                            p_reg_nxt = p_crnt;
                            q_reg_nxt = q_crnt;
                            S_reg_nxt = S_crnt;
                        end else begin
                            // R递增, r,t归零
                            R_nxt = R_crnt + 1;
                            r_nxt = 0;
                            t_nxt = 0;
                            state_nxt = INNER_LOOP;
                            // 恢复锁存值
                            p_nxt = p_reg_crnt;
                            q_nxt = q_reg_crnt;
                            S_nxt = S_reg_crnt;
                        end
                    end else begin
                        // r递增, t归零
                        r_nxt = r_crnt + 1;
                        t_nxt = 0;
                        state_nxt = INNER_LOOP;
                        p_nxt = p_reg_crnt;
                        q_nxt = q_reg_crnt;
                        S_nxt = S_reg_crnt;
                    end
                end else begin
                    // t递增
                    t_nxt = t_crnt + 1;
                    state_nxt = INNER_LOOP;
                    p_nxt = p_reg_crnt;
                    q_nxt = q_reg_crnt;
                    S_nxt = S_reg_crnt;
                end
            end

            // ---- INNER_LOOP: 内层循环 (通道维度) ----
            // 嵌套: for S(列) for q(输入通道) for p(输出通道)
            // 每个周期迭代一次, 共i=4次后跳回OUTER_LOOP
            INNER_LOOP:
            begin
                if (!await) begin            // 无反压
                    busy = 1'b1;             // 忙标志 = 读请求
                    if (i_crnt == i - 1) begin  // i=4次完成
                        i_nxt = 0;
                        state_nxt = OUTER_LOOP;
                    end else begin
                        i_nxt = i_crnt + 1;    // 继续内循环
                    end

                    if (lock_crnt) begin         // lock模式: 使用锁存入口值
                        if (p_crnt == p - 1) begin   // p到头
                            p_nxt = 0;
                            if (q_crnt == q - 1) begin  // q到头
                                q_nxt = 0;
                                if (S_crnt == S - 1) begin  // S也到头
                                    lock_nxt = 1'b0;       // 释放lock
                                    S_nxt = 0;
                                end else begin
                                    S_nxt = S_crnt + 1;
                                end
                            end else begin
                                q_nxt = q_crnt + 1;
                            end
                        end else begin
                            p_nxt = p_crnt + 1;
                        end
                     end
                end
            end

            // ---- DONE: 完成 ----
            DONE:
            begin
                done = 1'b1;
                state_nxt = IDLE;
            end
            default: state_nxt = IDLE;
        endcase
    end

    // ---- 索引输出 ----
    // filter_index = p_crnt + t_crnt * p
    //   含义: 在 p*t 输出通道平面内的线性索引
    //   p_crnt: 组内偏移 (0 ~ p-1); t_crnt * p: 跨组偏移
    // channel_index = q_crnt + r_crnt * q
    //   含义: 在 q*r 输入通道平面内的线性索引
    //   q_crnt: 组内偏移 (0 ~ q-1); r_crnt * q: 跨组偏移
    always @(*) begin
        filter_index  = p_crnt + (t_crnt * p);
        channel_index = q_crnt + (r_crnt * q);
        row_index     = R_crnt;
        col_index     = S_crnt;
    end

endmodule
