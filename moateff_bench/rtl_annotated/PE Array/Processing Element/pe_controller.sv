// ============================================================================
// 模块名称: pe_controller (PE 有限状态机控制器)
// 架构位置: pe.v 内部的子模块, 负责控制 PE 的所有操作时序
//
// 模块功能: 实现 PE 的六状态有限状态机 (FSM)
//           控制 ifmap_spad / filter_spad / psum_spad 的读写
//           生成 SPAD 地址、移位、累加、padding 等控制信号
//
// FSM 状态转换图:
//   IDLE ──(start)──> PROCESS ──(完成 q*S 行)──> ACCUMULATE
//   ACCUMULATE ──(完成 p 通道)──> STRIDE 或 PADDING
//   STRIDE ──(完成 U*q 步)──> PROCESS (新 ifmap 列)
//   PADDING ──(完成 V 周期)──> LOAD
//   LOAD ──(完成 n 次加载)──> IDLE 或 PROCESS
//
// 时序说明:
//   - 状态寄存器和计数器在 negedge clk 更新 (下降沿)
//   - 输出逻辑为组合电路 (always @*), 基于当前状态生成
//     控制信号在时钟沿之前稳定, PE 在下一个下降沿采样
// ============================================================================
module pe_controller
#(
    parameter F_WIDTH = 6,          // 输入通道数位宽
    parameter S_WIDTH = 4,          // 卷积核高度位宽 (ifmap行分片)
    parameter U_WIDTH = 3,          // 步幅位宽
    parameter n_WIDTH = 3,          // ifmap加载循环计数位宽
    parameter p_WIDTH = 5,          // 输出通道分片数位宽
    parameter q_WIDTH = 3,          // ifmap列分片数位宽
    parameter V_WIDTH = 2,          // padding计数位宽

    // SPAD 地址位宽参数
    parameter IFMAP_ADDR_WIDTH  = 4,  // ifmap SPAD 地址位宽
    parameter FILTER_ADDR_WIDTH = 8,  // filter SPAD 地址位宽
    parameter PSUM_ADDR_WIDTH   = 5   // psum SPAD 地址位宽
) (
    // ---------- 时钟与复位 ----------
    input wire clk,                              // 系统时钟 (下降沿有效)
    input wire reset,                            // 异步复位 (高电平有效)
    input wire start,                            // 启动信号: ~spads_empty (SPAD都就绪)
    input wire stall,                            // 暂停信号: spads_empty (SPAD不足,暂停)
    output reg busy,                             // 忙碌输出: 0=IDLE, 1=其他状态

    // ---------- 配置参数 ----------
    input wire [S_WIDTH - 1:0] S,                // 卷积核高度/ifmap行分片数
    input wire [F_WIDTH - 1:0] F,                // 输入通道数
    input wire [U_WIDTH - 1:0] U,                // 步幅
    input wire [n_WIDTH - 1:0] n,                // ifmap 加载循环次数 (行方向)
    input wire [p_WIDTH - 1:0] p,                // 输出通道分片数
    input wire [q_WIDTH - 1:0] q,                // ifmap 列分片数
    input wire [V_WIDTH - 1:0] V,                // padding 周期数 = p[1:0] * F[1:0]

    // ---------- FIFO 状态输入 ----------
    input wire ipsum_fifo_empty,                 // 输入psp FIFO空 (ACCUMULATE需非空)
    input wire opsum_fifo_full,                  // 输出psp FIFO满 (ACCUMULATE需非满)

    // ---------- 控制输出 ----------
    output reg reset_accumulation,               // 累加复位: PROCESS第一周期清零旧psp
    output reg accumulate_ipsum,                 // 累加使能: ACCUMULATE状态累加外部ipsum
    output reg reset_ifmap_spad,                 // ifmap SPAD 复位: LOAD状态清除旧数据
    output reg reset_filter_spad,                // filter SPAD 复位: LOAD最后周期清除

    // ---------- SPAD 地址输出 ----------
    // ifmap_addr = i_crnt: 指向当前行内位置 (0..S*q-1, 行优先展开)
    output wire [IFMAP_ADDR_WIDTH  - 1:0] ifmap_addr,
    // filter_addr = i_crnt * p + j_crnt: 二维ifmap位置映射到一维filter空间
    output wire [FILTER_ADDR_WIDTH - 1:0] filter_addr,
    // psum_addr = j_crnt: 指向当前输出通道的部分和
    output wire [PSUM_ADDR_WIDTH   - 1:0] psum_addr,

    // ---------- 控制输出 (时序控制) ----------
    output reg shift,                            // 移位使能: STRIDE状态时ifmap SPAD左移
    output reg rd_data,                          // 读数据使能: PROCESS状态时读SPAD数据
    output reg wr_psum,                          // 写psp使能: PROCESS状态时写回部分和
    output reg pad                               // padding标志: PADDING状态时输出填充零
);

    // ========================================================================
    // 状态编码: 6状态 FSM
    // IDLE:       空闲等待 SPAD 就绪
    // PROCESS:    执行 ifmap * filter 乘法和部分和写回
    // ACCUMULATE: 将本PE部分和与外部ipsum累加
    // STRIDE:     ifmap SPAD移位实现滑动窗口
    // PADDING:    输出零值部分和 (处理边界填充)
    // LOAD:       准备加载新的 ifmap/filter 数据
    // ========================================================================
    typedef enum logic [2:0] {IDLE, PROCESS, ACCUMULATE, STRIDE, PADDING, LOAD} state_t;
    state_t state_crnt, state_nxt;   // 当前状态和下一个状态

    // ---------- 计数器/寄存器 ----------
    // i_crnt: ifmap行内位置, 范围 0..S*q-1 (行优先展开)
    //         例如 S=4, q=3: 12个位置 = 3列 × 4行
    reg [IFMAP_ADDR_WIDTH  - 1:0] i_crnt, i_nxt;
    // j_crnt: 输出通道位置, 范围 0..p-1
    //         每个输出通道对应一个部分和累加器
    reg [PSUM_ADDR_WIDTH   - 1:0] j_crnt, j_nxt;

    // F_crnt: 输入通道循环计数, 范围 0..F-1
    reg [F_WIDTH - 1:0] F_crnt, F_nxt;
    // n_crnt: ifmap加载行数计数, 范围 0..n-1
    reg [n_WIDTH - 1:0] n_crnt, n_nxt;
    // V_crnt: padding周期计数, 范围 0..V (V = p[1:0]*F[1:0])
    reg [V_WIDTH - 1:0] V_crnt, V_nxt;
    // U_crnt: 步幅移位计数, 范围 0..U*q-1
    //         位宽 = U_WIDTH + q_WIDTH (如 U=3,q=3 -> 最大8)
    reg [U_WIDTH + q_WIDTH - 1:0] U_crnt, U_nxt;

    // ========================================================================
    // 状态转换逻辑 (时序逻辑)
    // always @(negedge clk or posedge reset): 下降沿更新, 异步复位
    // 将所有 nxt 值锁存到 crnt 值, 实现状态转移
    // ========================================================================
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            // 异步复位: 所有状态归零, 回到 IDLE
            state_crnt <= IDLE;
            i_crnt <= 'b0;
            j_crnt <= 'b0;
            F_crnt <= 'b0;
            U_crnt <= 'b0;
            n_crnt <= 'b0;
            V_crnt <= 'b0;
        end else begin
            state_crnt <= state_nxt;
            i_crnt <= i_nxt;
            j_crnt <= j_nxt;
            F_crnt <= F_nxt;
            U_crnt <= U_nxt;
            n_crnt <= n_nxt;
            V_crnt <= V_nxt;
        end
    end


    // ========================================================================
    // 状态输出和下一状态逻辑 (组合逻辑)
    // always @(*): 任何输入变化立即重新计算
    // 默认赋值: 所有输出无效, nxt保持不变
    // case(state_crnt): 根据当前状态决定输出和状态转移
    // ========================================================================
    always @(*) begin
        // ---------- 默认赋值: 所有输出无效 ----------
        busy    = 1'b1;       // 默认忙碌 (除IDLE外)
        shift   = 1'b0;       // 不移位
        rd_data = 1'b0;       // 不读
        wr_psum = 1'b0;       // 不写
        pad     = 1'b0;       // 不填充

        reset_accumulation = 1'b0;   // 不复位累加
        accumulate_ipsum   = 1'b0;   // 不累加外部ipsum

        // next值默认保持 (除非状态逻辑修改)
        state_nxt = state_crnt;
        i_nxt = i_crnt;
        j_nxt = j_crnt;
        F_nxt = F_crnt;
        U_nxt = U_crnt;
        n_nxt = n_crnt;
        V_nxt = V_crnt;

        reset_ifmap_spad  = 1'b0;    // 不复位ifmap SPAD
        reset_filter_spad = 1'b0;    // 不复位filter SPAD

        case (state_crnt)
            // ================================================================
            // IDLE 状态: 空闲, 等待 SPAD 数据就绪
            // busy=0: PE不忙, 可接受新任务
            // 转换: start=1 (SPAD就绪) -> PROCESS
            // ================================================================
            IDLE: begin
                busy = 1'b0;                // 空闲
                if (start) begin
                    state_nxt = PROCESS;    // SPAD就绪, 开始计算
                end
            end

            // ================================================================
            // PROCESS 状态: 执行 MAC 计算
            // 每周期: 读 ifmap[i] * filter[i*p+j], 写回 psum[j]
            // i: ifmap行内位置 (0..S*q-1), j: 输出通道 (0..p-1)
            // 条件: ~stall (SPAD不空)
            // reset_accumulation: i=0 时清零旧部分和
            // 转换路线A (j=p-1, i=S*q-1): 一轮完成 -> ACCUMULATE
            // 转换路线B (j=p-1, i<S*q-1): 下一行内位置, j归零
            // 转换路线C (j<p-1): 同一行, 下一输出通道
            // ================================================================
            PROCESS: begin
                if (~stall) begin            // SPAD不为空, 继续
                    // 每轮开始清零旧psp (i=0表示新输出通道组)
                    reset_accumulation = (i_crnt == 'b0) ? 1'b1 : 1'b0;
                    rd_data = 1'b1;          // 读SPAD数据
                    wr_psum = 1'b1;          // 写回部分和

                    if (j_crnt == (p - 1)) begin   // 当前输出通道组完成
                        if (i_crnt == (S * q - 1)) begin  // 所有ifmap位置完成
                            i_nxt = 'b0;
                            j_nxt = 'b0;
                            state_nxt = ACCUMULATE;    // 进入累加
                        end else begin
                            i_nxt = i_crnt + 1;        // 下一行内位置
                            j_nxt = 'b0;                // j归零
                        end
                    end else begin
                        j_nxt = j_crnt + 1;            // 下一输出通道
                    end
                end
                // stall=1: 保持当前状态, 等待SPAD数据
            end

            // ================================================================
            // ACCUMULATE 状态: 累加本PE部分和与外部输入部分和
            // 将本PE计算的 psum[j] 加上来自其他PE的 ipsum[j]
            // 条件: ipsum FIFO非空 AND opsum FIFO非满
            // j遍历输出通道 (0..p-1)
            // 转换路线A (j=p-1, F_crnt=F-1): 所有输入通道完成 -> PADDING
            // 转换路线B (j=p-1, F_crnt<F-1): 下一输入通道 -> STRIDE
            // 转换路线C (j<p-1): 同一输入通道, 下一输出通道
            // ================================================================
            ACCUMULATE: begin
                if ((~ipsum_fifo_empty) & (~opsum_fifo_full)) begin
                    accumulate_ipsum = 1'b1; // 累加使能
                    if (j_crnt == (p - 1)) begin   // 所有输出通道累加完成
                        j_nxt = 'b0;
                        if (F_crnt == (F - 1)) begin  // 所有输入通道完成
                            F_nxt = 'b0;
                            V_nxt = V;                 // 初始化padding计数
                            state_nxt = PADDING;       // 进入填充
                        end else begin
                            F_nxt = F_crnt + 1;        // 下一输入通道
                            state_nxt = STRIDE;        // 需要步幅移动窗口
                        end
                    end else begin
                        j_nxt = j_crnt + 1;
                    end
                end
                // FIFO条件不满足: 等待
            end

            // ================================================================
            // STRIDE 状态: ifmap 窗口滑动 (步幅 = U)
            // shift=1: ifmap SPAD每周期左移一列
            // 需要 U*q 次移位 (每个ifmap列需要U步stride, q个列)
            // 转换: U_crnt == U*q-1 (足够移位) -> PROCESS
            //        否则继续移位
            // ================================================================
            STRIDE: begin
                shift = 1'b1;              // 移位使能 (ifmap SPAD左移)
                if (U_crnt == (U * q) - 1) begin  // 移位次数达到
                    U_nxt = 'b0;
                    state_nxt = PROCESS;   // 窗口就绪, 开始新一轮计算
                end else begin
                    U_nxt = U_crnt + 1;    // 继续移位
                end
            end

            // ================================================================
            // PADDING 状态: 输出填充零 (边界处理)
            // pad=1: opsum输出0
            // 需要 V 个周期 (V = p[1:0] * F[1:0])
            // 转换: V_crnt==b00 -> LOAD (padding完成)
            //        否则继续padding
            // ================================================================
            PADDING: begin
                if (V_crnt == 2'b00) begin       // padding完成
                    V_nxt = 'b0;
                    state_nxt = LOAD;            // 进入加载阶段
                end else begin
                    pad = 1'b1;                  // 输出零
                    V_nxt = V_crnt + 1;          // 计数递增
                end
            end

            // ================================================================
            // LOAD 状态: 准备加载新数据
            // reset_ifmap_spad=1: 复位ifmap SPAD (准备接收新ifmap行)
            // n_crnt跟踪已加载的行数
            // 转换路线A (n_crnt=n-1): 所有行加载完成
            //        -> reset_filter_spad=1 -> IDLE (等待新filter)
            // 转换路线B (n_crnt<n-1): 更多行需加载 -> PROCESS
            //        (使用相同filter, 新的ifmap行)
            // ================================================================
            LOAD: begin
                reset_ifmap_spad = 1'b1;         // 复位 ifmap SPAD
                if (n_crnt == (n - 1)) begin     // 所有行加载完成
                    n_nxt = 'b0;
                    reset_filter_spad = 1'b1;    // 同时复位 filter SPAD
                    state_nxt = IDLE;            // 回到空闲
                end else begin
                    n_nxt = n_crnt + 1;          // 下一行
                    state_nxt = PROCESS;         // 继续计算 (filter不变)
                end
            end

            // 默认: 异常情况回到 IDLE
            default: begin
                state_nxt = IDLE;
            end
        endcase
    end

    // ========================================================================
    // SPAD 地址生成 (组合逻辑)
    // ifmap_addr = i_crnt: ifmap SPAD读地址
    //   行内位置展开: i从0到S*q-1
    //   例如 S=4,q=3: 12个位置 = 3列 x 4行
    //
    // filter_addr = i_crnt * p + j_crnt: filter SPAD读地址
    //   每个ifmap位置关联 p 个filter权重 (对应p个输出通道)
    //   所以 filter地址 = 行内位置 * 输出通道数 + 通道偏移
    //
    // psum_addr = j_crnt: psum SPAD地址
    //   j从0到p-1: 对应p个输出通道的部分和
    // ========================================================================
    assign ifmap_addr  = i_crnt;
    assign filter_addr = i_crnt * p + j_crnt;
    assign psum_addr   = j_crnt;

endmodule
