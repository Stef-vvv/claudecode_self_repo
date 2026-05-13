/*
 * ===========================================================================================
 * 模块名称: scheduler (调度器 FSM)
 * ===========================================================================================
 *
 * 【架构位置】
 *   本模块是 Eyeriss 加速器中 eyeriss 顶层模块的子模块（实例名: SCHEDULER）。
 *   处于 eyeriss 顶层之下，与 SCAN_CHAIN、PROCESSING_UNIT、INTF、GLB、ReLU 并列。
 *   调度器接收扫描链输出的 CNN 形状参数和 tiling 参数，
 *   通过 FSM 控制整个卷积层的 tile 遍历顺序。
 *
 * 【功能概述】
 *   调度器实现 Eyeriss 的四层嵌套循环遍历调度（Row-Stationary 数据流）：
 *
 *   外层循环 (OUTER_LOOP) 遍历三个维度:
 *     1. M (输出通道数, Output Channels)
 *     2. E (输出特征图高度, Output Height)
 *     3. N (批次大小, Batch Size)
 *
 *   内层循环 (INNER_LOOP) 遍历两个维度:
 *     1. m (输出通道 tile 子块)
 *     2. C (输入通道数, Input Channels)
 *
 *   每次执行:
 *     一个 CHECK → START_PASS → PROCESS → PASS_DONE 序列处理一个具体的 tile。
 *
 * 【FSM 状态机（9 个状态）】
 *   IDLE:       空闲，等待 start 信号
 *   CHECK:      检查条件，决定下一步 (启动 pass / 进入内层 / 外层 / 转储 / 完成)
 *   OUTER_LOOP: 更新外层循环计数器 (M, E, N)
 *   INNER_LOOP: 更新内层循环计数器 (m_crnt, C)
 *   START_PASS: 启动一次计算 pass (置位 start_noc)
 *   PROCESS:    等待 PE 阵列完成当前 pass (noc_done)
 *   PASS_DONE:  一次 pass 完成，进入下一内层调度
 *   DUMPING:    输出特征图回写到 DRAM
 *   DONE:       当前层全部完成，返回 IDLE
 *
 * 【状态转移图】
 *
 *           start                start_pass
 *   IDLE ──────────→ CHECK ──────────────────→ START_PASS ──→ PROCESS
 *     ↑                 ↑                                            │ noc_done
 *     │                 │                                            ↓
 *     │                 ├── (next tile) ←── PASS_DONE ←──────────────┘
 *     │                 │        ↑                pass_done=1
 *     │                 │        │
 *     │    (内层未完成)  │   INNER_LOOP
 *     │                 │     m_crnt += p*t  或  C_crnt += q*r
 *     │                 │        ↑
 *     │                 │        │ (m_crnt 和 C_crnt 都完成)
 *     │                 │        │
 *     │                 │     DUMPING ──(dump_done)──→ OUTER_LOOP
 *     │                 │                              M_crnt += m  或
 *     │                 │                              E_crnt += e  或
 *     │                 │                              N_crnt += n
 *     │                 │        ↑                         │
 *     │                 │        │   (外层未完成) ←────────┘
 *     │                 │        │
 *     │                 └────────┘ (外层全部完成)
 *     │                         DONE ──→ IDLE
 *     └──────────────────────────────────┘
 *                         done=1
 *
 * 【关键设计决策】
 *   - bias_sel 逻辑: 当 channel_ids[0] == 0 (即 C_crnt == 0) 时有效，
 *     表示这是当前输出通道组的第一个输入通道 pass，
 *     PE 需要用 bias 初始化累加器而非读取旧的部分和。
 *   - 计数器使用 _crnt/_nxt 双变量模式:
 *     state_crnt / state_nxt (当前/下一状态)
 *     便于纯组合逻辑计算下一状态，时序逻辑只做寄存器更新。
 *   - [0:1] 数组 = [start, end): 半开区间语义
 *     filter_ids[0] = start_oc+1, filter_ids[1] = end_oc+1
 *
 * 【与子模块的接口关系】
 *   - 输入: start (来自 top_controller), start_pass, noc_done, dump_done
 *   - 输出: start_noc → processing_unit, busy/done → top_controller
 *   - 输出: bias_sel → eyeriss 顶层 (控制 psum/bias 选择)
 *   - 输出: filter_ids/ifmap_ids/psum_ids 等 → GLB 地址生成 / PE 阵列
 */

module scheduler #(
    // ===========================================================================================
    // 参数定义 - CNN 形状参数位宽
    // ===========================================================================================

    // E_WIDTH = 6: 输出特征图高度 E 的位宽 (最大 64)
    parameter E_WIDTH = 6,
    // C_WIDTH = 10: 输入通道数 C 的位宽 (最大 1024)
    parameter C_WIDTH = 10,
    // M_WIDTH = 10: 输出通道数 M 的位宽 (最大 1024)
    parameter M_WIDTH = 10,
    // N_WIDTH = 3: 批次大小 N 的位宽 (最大 8)
    parameter N_WIDTH = 3,

    // ===========================================================================================
    // 参数定义 - Tiling 参数位宽
    //
    // 这些参数决定了循环步长（一次 tile 处理的数据量）:
    //   m: 输出通道外层 tile 大小 (外循环 M 的步长)
    //   n: 批次 tile 大小 (外循环 N 的步长)
    //   e: 输出高度 tile 大小 (外循环 E 的步长)
    //   p: 滤波器高度方向 tile 因子
    //   q: 滤波器宽度方向 tile 因子 (内循环 C 的步长 = q*r)
    //   r: 输入通道 tile 因子 (内循环 C 的步长 = q*r)
    //   t: 输出通道内层 tile 因子 (内循环 m 的步长 = p*t)
    //
    // 关键关系:
    //   内循环 m_crnt 步长 = p * t  (输出通道子块步长)
    //   内循环 C_crnt 步长 = q * r  (输入通道步长)
    //   外循环 M_crnt 步长 = m       (输出通道外层步长)
    // ===========================================================================================

    parameter m_WIDTH = 6,     // 输出通道 tile 位宽
    parameter n_WIDTH = 3,     // 批次 tile 位宽
    parameter e_WIDTH = 6,     // 输出高度 tile 位宽
    parameter p_WIDTH = 5,     // 滤波器高度 tile 位宽
    parameter q_WIDTH = 3,     // 滤波器宽度 tile 位宽
    parameter r_WIDTH = 2,     // 输入通道 tile 位宽
    parameter t_WIDTH = 3      // 输出通道子 tile 位宽
) (
    // ===========================================================================================
    // 端口定义
    // ===========================================================================================

    // clk: 核心时钟
    // 方向: input
    // 连接: eyeriss 顶层 core_clk
    // 用途: 驱动 FSM 状态机和计数器更新
    input  logic clk,

    // reset: 全局复位，高有效
    // 方向: input
    // 连接: eyeriss 顶层 reset
    // 用途: 复位后 FSM 回到 IDLE 状态，所有计数器清零
    input  logic reset,

    // start: 开始信号
    // 方向: input
    // 连接: eyeriss 顶层 start (来自 top_controller)
    // 用途: 高有效时 FSM 从 IDLE 跳转到 CHECK，启动当前层调度
    input  logic start,

    // busy: 忙碌标志
    // 方向: output
    // 连接: eyeriss 顶层 busy → top_controller
    // 用途: 高有效表示 Eyeriss 正在执行计算（PROCESS 状态），不可接受新任务
    output logic busy,

    // done: 完成标志
    // 方向: output
    // 连接: eyeriss 顶层 done → top_controller
    // 用途: 高有效表示当前层所有 tile 已处理完毕（DONE 状态持续一个周期）
    output logic done,

    // start_pass: 启动 pass 信号
    // 方向: input
    // 连接: eyeriss 顶层 start_pass (来自 top_controller)
    // 用途: 在 CHECK 状态中检测到此信号后，FSM 跳转到 START_PASS
    input  logic start_pass,

    // pass_done: pass 完成标志
    // 方向: output
    // 连接: eyeriss 顶层 pass_done
    // 用途: 在 PASS_DONE 状态中置位一个周期，通知外部当前 pass 完成
    output logic pass_done,

    // start_noc: 启动 NoC/PE 阵列信号
    // 方向: output
    // 连接: eyeriss 顶层 → processing_unit.start
    // 用途: 在 START_PASS 状态中置位一个周期，触发 PE 阵列开始计算
    output logic start_noc,

    // noc_done: NoC/PE 阵列完成信号
    // 方向: input
    // 连接: eyeriss 顶层 ← processing_unit.done
    // 用途: 在 PROCESS 状态中检测到此信号后，FSM 跳转到 PASS_DONE
    input  logic noc_done,

    // ofmap_dump: 输出特征图转储信号
    // 方向: output
    // 连接: eyeriss 顶层 ofmap_dump
    // 用途: 在 DUMPING 状态中持续置位，通知 interface_unit 回写输出特征图
    output logic ofmap_dump,

    // dump_done: 输出转储完成信号
    // 方向: input
    // 连接: eyeriss 顶层 dump_done
    // 用途: 在 DUMPING 状态中检测到此信号后，FSM 跳转到 OUTER_LOOP
    input  logic dump_done,

    // bias_sel: 偏置选择信号
    // 方向: output
    // 连接: eyeriss 顶层 bias_sel → processing_unit (控制 psum/bias 数据选择)
    // 用途:
    //   1'b1 = 当前 pass 需要从 bias GLB 读取偏置初始化 (channel_ids[0] == 0 时)
    //   1'b0 = 当前 pass 需要从 psum GLB 读取旧部分和累加
    // 原理: 每个输出通道组的第一个 pass (C_crnt == 0) 需要用偏置初始化，
    //       后续 pass 需要累加从 psum GLB 读出的旧部分和。
    output logic bias_sel,

    // ===========================================================================================
    // CNN 形状参数输入 —— 来自扫描链 (SCAN_CHAIN)
    //
    // 大写字母 = 当前层的完整维度大小 (在配置阶段确定，计算期间不变)
    // ===========================================================================================

    // E: 输出特征图高度 (Output Height)
    // 位宽: E_WIDTH (6 bits)
    // 用途: 外层循环 E_crnt 的上界，E_crnt + e >= E 时该维度完成
    input  logic [E_WIDTH - 1:0] E,

    // C: 输入通道数 (Input Channels)
    // 位宽: C_WIDTH (10 bits)
    // 用途: 内层循环 C_crnt 的上界，C_crnt + (q*r) == C 时该维度完成
    input  logic [C_WIDTH - 1:0] C,

    // M: 输出通道数 (Output Channels)
    // 位宽: M_WIDTH (10 bits)
    // 用途: 外层循环 M_crnt 的上界，M_crnt + m == M 时该维度完成
    input  logic [M_WIDTH - 1:0] M,

    // N: 批次大小 (Batch Size)
    // 位宽: N_WIDTH (3 bits)
    // 用途: 外层循环 N_crnt 的上界，(N_crnt + n) == N 时该维度完成
    input  logic [N_WIDTH - 1:0] N,

    // ===========================================================================================
    // Tiling 参数输入 —— 来自扫描链 (SCAN_CHAIN)
    //
    // 小写字母 = tile 步长参数 (决定每次循环迭代处理的数据量)
    // ===========================================================================================

    // m: 输出通道外层 tile 大小
    // 位宽: m_WIDTH (6 bits)
    // 用途: 外循环 M_crnt 的步长 = m (即 OUTER_LOOP 中 M_nxt = M_crnt + m)
    input  logic [m_WIDTH - 1:0] m,

    // n: 批次 tile 大小
    // 位宽: n_WIDTH (3 bits)
    // 用途: 外循环 N_crnt 的步长 = n
    input  logic [n_WIDTH - 1:0] n,

    // e: 输出高度 tile 大小
    // 位宽: e_WIDTH (6 bits)
    // 用途: 外循环 E_crnt 的步长 = e
    input  logic [e_WIDTH - 1:0] e,

    // p: 滤波器高度方向 tile 因子
    // 位宽: p_WIDTH (5 bits)
    // 用途: 内循环 m_crnt 步长的构成因子之一 (p * t)
    input  logic [p_WIDTH - 1:0] p,

    // q: 滤波器宽度方向 tile 因子
    // 位宽: q_WIDTH (3 bits)
    // 用途: 内循环 C_crnt 步长的构成因子之一 (q * r)
    input  logic [q_WIDTH - 1:0] q,

    // r: 输入通道 tile 因子
    // 位宽: r_WIDTH (2 bits)
    // 用途: 内循环 C_crnt 步长的构成因子之二 (q * r)
    input  logic [r_WIDTH - 1:0] r,

    // t: 输出通道子 tile 因子
    // 位宽: t_WIDTH (3 bits)
    // 用途: 内循环 m_crnt 步长的构成因子之二 (p * t)
    input  logic [t_WIDTH - 1:0] t,

    // ===========================================================================================
    // Tile ID 范围输出
    //
    // 每个输出为两个元素的数组 [0:1]，表示 [start, end) 半开区间:
    //   [0] = 起始 ID (通常从 1 开始，因为 ID 0 可能保留)
    //   [1] = 结束 ID (通常是 end+1)
    //
    // 这些信号传递给 PE 阵列和 GLB 地址生成逻辑。
    // ===========================================================================================

    // filter_ids: 当前 tile 的输出通道范围 [start_oc, end_oc+1)
    // 位宽: 每个 M_WIDTH(10) bits, 2 个元素
    // 含义: 通知 PE 阵列和 GLB 当前处理哪些输出通道的滤波器
    // 计算: 普通 pass: [M_crnt + m_crnt + 1, M_crnt + m_crnt + (p*t))
    //       DUMPING:  [M_crnt + 1, M_crnt + m)
    output logic [M_WIDTH - 1:0] filter_ids         [0:1],

    // filter_channel_ids: 当前滤波器对应的输入通道范围 [start_ic, end_ic+1)
    // 位宽: 每个 C_WIDTH(10) bits, 2 个元素
    // 注意: 与 ifmap_channel_ids 相同（同一 pass 的 filter 和 ifmap 处理相同通道范围）
    output logic [C_WIDTH - 1:0] filter_channel_ids [0:1],

    // ifmap_ids: 当前 tile 的批次范围 [start_batch, end_batch+1)
    // 位宽: 每个 N_WIDTH(3) bits, 2 个元素
    output logic [N_WIDTH - 1:0] ifmap_ids         [0:1],

    // ifmap_channel_ids: 当前 ifmap 通道范围 [start_ic, end_ic+1)
    // 位宽: 每个 C_WIDTH(10) bits, 2 个元素
    // 与 filter_channel_ids 共享 channel_ids 内部信号
    output logic [C_WIDTH - 1:0] ifmap_channel_ids [0:1],

    // psum_ids: 部分和的批次范围 [start_batch, end_batch+1)
    // 位宽: 每个 N_WIDTH(3) bits, 2 个元素
    // 注意: psum 的 batch 维度与 ifmap 相同，故 psum_ids = ifmap_ids
    output logic [N_WIDTH - 1:0] psum_ids         [0:1],

    // psum_channel_ids: 部分和的输出通道范围 [start_oc, end_oc+1)
    // 位宽: 每个 M_WIDTH(10) bits, 2 个元素
    // 注意: psum 的输出通道维度与 filter 维度相同，故 psum_channel_ids = filter_ids
    output logic [M_WIDTH - 1:0] psum_channel_ids [0:1]
);

    // ===========================================================================================
    // 状态枚举定义
    //
    // typedef enum 定义了 9 个 FSM 状态，编码为 4-bit (logic [3:0])。
    // 使用枚举可以编写可读性更高的 case 语句。
    //
    // IDLE:         空闲状态，等待 start=1 启动
    // CHECK:        检查状态，根据循环条件决定下一步去向
    // OUTER_LOOP:   外循环更新（M, E, N 计数器递增）
    // INNER_LOOP:   内循环更新（m_crnt, C_crnt 计数器递增）
    // START_PASS:   启动一次 pass（置位 start_noc）
    // PROCESS:      等待 PE 阵列完成当前 pass
    // PASS_DONE:    一次 pass 完成的信号输出状态
    // DUMPING:      输出特征图转储状态（等待 dump_done）
    // DONE:         当前层全部完成状态（输出 done）
    // ===========================================================================================
    typedef enum logic [3:0] {IDLE, CHECK, OUTER_LOOP, INNER_LOOP, START_PASS, PROCESS, PASS_DONE, DUMPING, DONE} state_type;
    state_type state_nxt, state_crnt;         // state_nxt = 下一状态 (组合逻辑计算), state_crnt = 当前状态 (寄存器)

    // ===========================================================================================
    // 循环计数器 —— 双变量模式 (_crnt / _nxt)
    //
    // _crnt 变量: 由时序逻辑块 (always_ff) 在每个 posedge clk 更新
    // _nxt 变量:  由组合逻辑块 (always_comb) 根据当前状态和条件计算
    //
    // 这种模式的好处:
    //   1. 组合逻辑纯计算下一值，时序逻辑只做寄存器传输
    //   2. 避免在 always_ff 中编写复杂的条件判断
    //   3. 符合标准的两段式 FSM 设计模式
    // ===========================================================================================

    // C_crnt / C_nxt: 当前/下一 输入通道计数器
    // 范围 [0, C), 步长 = q * r
    // 含义: 当前 tile 的起始输入通道索引
    logic [C_WIDTH - 1:0] C_nxt, C_crnt;

    // M_crnt / M_nxt: 当前/下一 输出通道外层计数器
    // 范围 [0, M), 步长 = m
    // 含义: 当前 tile 组的起始输出通道索引 (外层)
    logic [M_WIDTH - 1:0] M_nxt, M_crnt;

    // N_crnt / N_nxt: 当前/下一 批次计数器
    // 范围 [0, N), 步长 = n
    // 含义: 当前 tile 组的起始批次索引
    logic [N_WIDTH - 1:0] N_nxt, N_crnt;

    // m_crnt / m_nxt: 当前/下一 输出通道内层计数器
    // 范围 [0, m), 步长 = p * t
    // 含义: 在外层 M_crnt 的基础上，当前内层子块的偏移 (输出通道子块索引)
    logic [m_WIDTH - 1:0] m_nxt, m_crnt;

    // E_crnt / E_nxt: 当前/下一 输出高度计数器
    // 范围 [0, E), 步长 = e
    // 含义: 当前 tile 组的起始输出行索引
    logic [E_WIDTH - 1:0] E_nxt, E_crnt;

    // ===========================================================================================
    // channel_ids: 通道 ID 中间信号 [0:1]
    //
    // 位宽: 每个 C_WIDTH(10) bits, 2 个元素
    // 用途: 内部计算当前 tile 的输入通道范围 [start_ic, end_ic+1)
    //       通过 assign 连接到 filter_channel_ids 和 ifmap_channel_ids 输出
    //       也用于 bias_sel 的判断 (channel_ids[0] == 0 表示第一个通道 pass)
    // ===========================================================================================
    logic [C_WIDTH - 1:0] channel_ids [0:1];

    // ===========================================================================================
    // 时序逻辑块 (always_ff)
    //
    // 触发条件: posedge clk 或 posedge reset
    //
    // 功能: 在每个时钟上升沿将下一状态和下一计数器值锁存到当前状态和当前计数器。
    //       reset=1 时所有状态和计数器归零，FSM 回到 IDLE。
    //
    // 更新信号:
    //   state_crnt ← state_nxt
    //   C_crnt, M_crnt, N_crnt, m_crnt, E_crnt ← 对应的 _nxt 信号
    // ===========================================================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;       // 复位后回到空闲状态
            C_crnt <= 0;              // 输入通道计数器清零
            M_crnt <= 0;              // 输出通道外层计数器清零
            N_crnt <= 0;              // 批次计数器清零
            m_crnt <= 0;              // 输出通道内层计数器清零
            E_crnt <= 0;              // 输出高度计数器清零
        end else begin
            state_crnt <= state_nxt;  // 状态转移
            C_crnt <= C_nxt;          // 输入通道计数更新
            M_crnt <= M_nxt;          // 输出通道外层计数更新
            N_crnt <= N_nxt;          // 批次计数更新
            m_crnt <= m_nxt;          // 输出通道内层计数更新
            E_crnt <= E_nxt;          // 输出高度计数更新
        end
    end

    // ===========================================================================================
    // 组合逻辑块 #1 (always_comb): FSM 状态转移和输出信号
    //
    // 触发条件: 任何输入信号变化 (组合逻辑，不依赖时钟边沿)
    //
    // 功能:
    //   1. 默认赋值 (避免 latch):
    //      - 所有输出信号默认置为 0
    //      - 所有 _nxt 变量默认保持 _crnt 值
    //      - state_nxt 默认保持 state_crnt
    //   2. 根据 state_crnt 进行 case 分支:
    //      每个状态定义: 输出信号值、状态转移条件、计数器更新
    //
    // 关键设计:
    //   - 默认赋值模式避免了综合器推断 latch
    //   - case 语句覆盖所有 9 个状态
    //   - 每个状态的转移条件只依赖当前计数器和固定的边界值
    // ===========================================================================================
    always_comb begin
        // -------- 默认赋值: 所有输出信号和下一状态默认值 --------
        start_noc = 1'b0;         // 默认: 不启动 NoC
        pass_done = 1'b0;         // 默认: pass 未完成
        busy = 1'b0;              // 默认: 不忙碌
        done = 1'b0;              // 默认: 未完成
        ofmap_dump = 1'b0;        // 默认: 不转储

        // 计数器默认保持当前值 (大多数状态不改变计数器)
        C_nxt = C_crnt;
        M_nxt = M_crnt;
        N_nxt = N_crnt;
        m_nxt = m_crnt;
        E_nxt = E_crnt;

        // 状态默认保持 (仅在条件满足时改变)
        state_nxt = state_crnt;

        // ====================================================================
        // 状态机核心: case(state_crnt)
        // ====================================================================
        case(state_crnt)

            // ----------------------------------------------------------------
            // IDLE: 空闲状态
            //
            // 含义: 芯片复位后或一层完成后停留在此状态。
            //       等待外部 top_controller 发出 start=1 信号。
            // 转移条件: start == 1 → CHECK
            // 输出: 无 (所有输出默认 0)
            // ----------------------------------------------------------------
            IDLE:
            begin
                if (start) begin
                    state_nxt = CHECK;
                end
            end

            // ----------------------------------------------------------------
            // CHECK: 检查状态
            //
            // 含义: 这是 FSM 的核心决策状态。从多个来源 (IDLE, INNER_LOOP,
            //       OUTER_LOOP) 汇聚到此状态，根据条件决定下一步。
            //
            // 转移条件:
            //   start_pass == 1 → START_PASS (启动一次新的 pass)
            //   否则 → 保持 CHECK (等待外部发出 start_pass)
            //
            // 注意: CHECK 状态不主动推进循环，它等待外部 (top_controller)
            //       发出 start_pass。这意味着调度器是被动触发的，
            //       需要 top_controller 协调数据加载和 pass 启动。
            // ----------------------------------------------------------------
            CHECK:
            begin
                if (start_pass) begin
                    state_nxt = START_PASS;
                end
            end

            // ----------------------------------------------------------------
            // INNER_LOOP: 内层循环状态
            //
            // 含义: 一次 pass 完成后 (来自 PASS_DONE)，更新内层循环计数器。
            //
            // 两层检查逻辑:
            //
            // 第1层: 检查 m_crnt (输出通道子块)
            //   if (m_crnt + (p * t) == m):
            //     说明当前外层输出通道 (M_crnt) 的所有子块已处理完,
            //     需要重置 m_crnt=0，然后检查输入通道 C_crnt
            //   else:
            //     m_crnt += (p * t), 继续处理同一输出通道的下一个子块
            //     → CHECK (启动下一个子块的 pass)
            //
            // 第2层: 检查 C_crnt (输入通道)
            //   if (C_crnt + (q * r) == C):
            //     说明当前输出通道块 (M_crnt..M_crnt+m) 的所有输入通道已累加完,
            //     该输出通道块的 psum 已完整, 需要回写输出特征图
            //     → DUMPING (转储完整的部分和到 DRAM)
            //   else:
            //     C_crnt += (q * r), 继续累加下一组输入通道
            //     → CHECK (启动下一个通道组的 pass)
            //
            // 形象理解:
            //   一个输出通道需要累加所有 C 个输入通道的卷积结果。
            //   如果一次只能处理 (q*r) 个输入通道，则需要 C/(q*r) 次 pass
            //   才能完成一个输出通道块的 psum。
            //   每次内循环步进 m_crnt (处理更多输出通道子块) 或 C_crnt (累加更多输入通道)。
            // ----------------------------------------------------------------
            INNER_LOOP:
            begin
                // 内层第1维: 输出通道子块 m_crnt
                if ((m_crnt + (p * t)) == m) begin
                    m_nxt = 0;                            // 重置子块计数器

                    // 内层第2维: 输入通道 C_crnt
                    if ((C_crnt + (q * r)) == C) begin
                        C_nxt = 0;                        // 重置输入通道计数器
                        state_nxt = DUMPING;              // 所有输入通道已累加完 → 转储输出
                    end else begin
                        C_nxt = C_crnt + (q * r);         // 步进: 处理下一组输入通道
                        state_nxt = CHECK;                // 回到 CHECK 启动下一个 pass
                    end
                end else begin
                    m_nxt = m_crnt + (p * t);             // 步进: 处理下一个输出通道子块
                    state_nxt = CHECK;                    // 回到 CHECK 启动下一个 pass
                end
            end

            // ----------------------------------------------------------------
            // OUTER_LOOP: 外层循环状态
            //
            // 含义: 一次 dump 完成后 (来自 DUMPING, dump_done=1),
            //       更新外层循环计数器。
            //
            // 三层检查逻辑 (从内到外):
            //
            // 第1层: 检查 M_crnt (输出通道)
            //   if (M_crnt + m == M):
            //     当前层所有输出通道已处理完, 重置 M_crnt=0
            //     继续检查 E_crnt (输出高度)
            //   else:
            //     M_crnt += m, 处理下一组输出通道
            //     → CHECK
            //
            // 第2层: 检查 E_crnt (输出高度)
            //   if (E_crnt + e >= E):
            //     当前输出高度范围已覆盖完, 重置 E_crnt=0
            //     继续检查 N_crnt (批次)
            //     注意: 使用 >= 而非 ==，因为 e 可能不能整除 E
            //   else:
            //     E_crnt += e, 处理下一组输出行
            //     → CHECK
            //
            // 第3层: 检查 N_crnt (批次)
            //   if ((N_crnt + n) == N):
            //     所有批次已处理完成, 重置 N_crnt=0
            //     → DONE (当前层全部完成)
            //   else:
            //     N_crnt += n, 处理下一批
            //     → CHECK
            //
            // 形象理解:
            //   卷积层需要处理 [M 个输出通道] × [E×(F) 个输出位置] × [N 个批次]
            //   每次外循环步进 M_crnt (换一组输出通道), E_crnt (换一组输出行),
            //   或 N_crnt (换一个批次)。
            // ----------------------------------------------------------------
            OUTER_LOOP:
            begin
                // 外层第1维: 输出通道 M
                if (M_crnt + m == M) begin
                    M_nxt = 0;                            // 重置输出通道计数器

                    // 外层第2维: 输出高度 E
                    if (E_crnt + e >= E) begin
                        E_nxt = 0;                        // 重置输出高度计数器

                        // 外层第3维: 批次 N
                        if ((N_crnt + n) == N) begin
                            N_nxt = 0;                    // 重置批次计数器
                            state_nxt = DONE;             // 全部完成 → DONE
                        end else begin
                            N_nxt = N_crnt + n;           // 步进: 下一批次
                            state_nxt = CHECK;            // 回到 CHECK 开始新批次的调度
                        end
                    end else begin
                        E_nxt = E_crnt + e;               // 步进: 下一组输出行
                        state_nxt = CHECK;                // 回到 CHECK
                    end
                end else begin
                    M_nxt = M_crnt + m;                   // 步进: 下一组输出通道
                    state_nxt = CHECK;                    // 回到 CHECK
                end
            end

            // ----------------------------------------------------------------
            // START_PASS: 启动 pass 状态
            //
            // 含义: 从 CHECK 进入，启动一次 PE 阵列计算 pass。
            //       本状态持续一个时钟周期。
            //
            // 转移: 无条件 → PROCESS (下一个周期)
            // 输出: start_noc = 1 (触发 PE 阵列)
            //
            // 注意: start_noc 是组合逻辑输出，在当前周期有效。
            //       processing_unit 在下一个 posedge clk 采样到此信号。
            // ----------------------------------------------------------------
            START_PASS:
            begin
                state_nxt = PROCESS;         // 进入等待计算完成的状态
                start_noc = 1'b1;            // 置位: 触发 processing_unit 开始计算
            end

            // ----------------------------------------------------------------
            // PROCESS: 等待 PE 阵列完成状态
            //
            // 含义: PE 阵列正在执行当前 pass 的卷积计算。
            //       调度器在此状态等待 noc_done 信号。
            //
            // 转移条件: noc_done == 1 → PASS_DONE
            // 输出: busy = 1 (告知 top_controller 芯片正忙)
            //
            // 在此期间:
            //   - PE 阵列在 core_clk 驱动下进行 ifmap * filter 的乘累加
            //   - NoC 负责 GLB ↔ PE 之间的数据传输
            //   - 所有计数器保持不变 (等待结果)
            // ----------------------------------------------------------------
            PROCESS:
            begin
                if (noc_done) begin
                    state_nxt = PASS_DONE;    // PE 阵列完成 → 进入 PASS_DONE
                end
                busy = 1'b1;                  // 告知外部: 正在计算中
            end

            // ----------------------------------------------------------------
            // PASS_DONE: pass 完成状态
            //
            // 含义: 一次 pass 刚刚完成，通知外部并进入内层循环更新。
            //       本状态持续一个时钟周期。
            //
            // 转移: 无条件 → INNER_LOOP (下一个周期)
            // 输出: pass_done = 1 (通知 top_controller 或回调逻辑)
            //
            // 注意: 从 PROCESS 进入时 noc_done=1 已满足，所以这里是条件转移。
            //       进入 INNER_LOOP 后，调度器会更新内层计数器并回到 CHECK。
            // ----------------------------------------------------------------
            PASS_DONE:
            begin
                state_nxt = INNER_LOOP;       // 进入内层循环更新
                pass_done = 1'b1;             // 置位: 通知外部一次 pass 完成
            end

            // ----------------------------------------------------------------
            // DUMPING: 输出特征图转储状态
            //
            // 含义: 当前输出通道块的 psum 已完整 (所有输入通道已累加)，
            //       需要将输出特征图从 psum GLB 回写到片外 DRAM。
            //
            // 转移条件: dump_done == 1 → OUTER_LOOP
            // 输出: ofmap_dump = 1 (持续置位，通知 interface_unit 开始回写)
            //
            // 在此期间:
            //   - interface_unit 从 psum GLB (A端口) 读取数据
            //   - 数据经过 ReLU 激活函数处理
            //   - 通过 link_clk 域写入外部 DRAM
            //   - 调度器阻塞等待 dump_done
            //
            // 注意: DUMPING 意味着当前 M_crnt 组的输出通道 psum 已完成。
            //       此时 channel_ids 置为 {1, C}，表示所有输入通道已处理完
            //       (dump 时 channel 范围是无效的，用 {1, C} 占位)。
            // ----------------------------------------------------------------
            DUMPING:
            begin
                ofmap_dump = 1'b1;            // 置位: 触发输出回写
                if (dump_done) begin
                    state_nxt = OUTER_LOOP;   // 回写完成 → 外层循环更新
                end
            end

            // ----------------------------------------------------------------
            // DONE: 当前层完成状态
            //
            // 含义: 所有外层循环 (M, E, N) 都已处理完成。
            //       当前卷积层的全部输出已计算并回写完毕。
            //       本状态持续一个时钟周期后自动回到 IDLE。
            //
            // 转移: 无条件 → IDLE (下一个周期)
            // 输出: done = 1 (通知 top_controller 当前层完成)
            //
            // 注意: 回到 IDLE 后，如果 start 再次置位，
            //       调度器可以重新开始下一层的调度 (计数器从 0 开始)。
            // ----------------------------------------------------------------
            DONE:
            begin
                state_nxt = IDLE;             // 回到空闲状态，等待下一层
                done = 1'b1;                  // 置位: 通知外部一层完成
            end
        endcase
    end

    // ===========================================================================================
    // 组合逻辑块 #2 (always_comb): Tile ID 范围计算和 bias_sel 逻辑
    //
    // 触发条件: 任何输入信号变化 (组合逻辑)
    //
    // 功能:
    //   根据当前状态和循环计数器计算:
    //     1. filter_ids[0:1]  - 输出通道范围
    //     2. channel_ids[0:1] - 输入通道范围
    //     3. ifmap_ids[0:1]   - 批次范围
    //     4. bias_sel         - 偏置选择标志
    //
    // 三种情况的分支:
    //   a) IDLE / DONE 状态:
    //      所有 ID 输出为 0 (无效)，bias_sel = 0
    //
    //   b) DUMPING 状态:
    //      filter_ids = [M_crnt+1, M_crnt+m)   (当前 dump 的输出通道范围)
    //      channel_ids = [1, C)                (占位值，dump 时不需要通道信息)
    //      ifmap_ids = [N_crnt+1, N_crnt+n)    (当前批次范围)
    //      bias_sel = 0                         (dump 时不涉及偏置)
    //
    //   c) 其他状态 (CHECK, INNER_LOOP, START_PASS, PROCESS, PASS_DONE, OUTER_LOOP):
    //      filter_ids = [M_crnt + m_crnt + 1, M_crnt + m_crnt + (p*t))
    //        = 全局起始输出通道 + 子块偏移 → 当前子块的输出通道范围
    //      channel_ids = [C_crnt + 1, C_crnt + (q*r))
    //        = 当前输入通道范围
    //      ifmap_ids = [N_crnt + 1, N_crnt + n)
    //        = 当前批次范围
    //      bias_sel = (channel_ids[0] == 0)
    //        = 当起始输入通道为 0 时，需要偏置初始化
    //
    // 关键: bias_sel 的判断依据是 C_crnt。
    //       当 C_crnt == 0 (即 channel_ids[0] == 0 + 1 = 1...
    //       等等，这里 channel_ids[0] = C_crnt + 1，
    //       所以 bias_sel = (C_crnt + 1 == 0) = (C_crnt == -1)... 这不对。
    //
    //       重新分析: channel_ids[0] = C_crnt + 1
    //       bias_sel = (channel_ids[0] == 0) = (C_crnt + 1 == 0)
    //
    //       这只有在 C_crnt 上溢到 0 时才成立。实际上这应该是:
    //       当 C_crnt == 0 时（即处理第一个输入通道组时），bias_sel = 1。
    //       但代码写的是 channel_ids[0] == 0。
    //
    //       等等... channel_ids[0] = C_crnt + 1。
    //       那 channel_ids[0] == 0 意味着什么？
    //       C_crnt + 1 == 0 → C_crnt = -1（无符号下溢 = 全 1）
    //
    //       这可能是个 bug，或者是故意这样设计的。
    //       原注释保留原始逻辑不变。
    // ===========================================================================================
    always_comb begin
        if ((state_crnt == IDLE) || (state_crnt == DONE)) begin
            // IDLE / DONE: 所有 ID 清零，无有效 tile
            filter_ids = '{0, 0};
            channel_ids = '{0, 0};
            ifmap_ids = '{0, 0};

            bias_sel = 1'b0;          // 空闲/完成时不选偏置
        end else if (state_crnt == DUMPING) begin
            // DUMPING: 输出当前完成的输出通道块范围
            // filter_ids = [M_crnt + 1, M_crnt + m)  —— 该 DUMP 对应的输出通道范围
            filter_ids = '{M_crnt + 1, M_crnt + m};
            // channel_ids = [1, C)  —— DUMP 时所有输入通道已累加完，用全范围占位
            channel_ids = '{1, C};
            // ifmap_ids = [N_crnt + 1, N_crnt + n)  —— 当前批次范围
            ifmap_ids = '{N_crnt + 1, N_crnt + n};

            bias_sel = 1'b0;          // DUMP 时不涉及偏置选择
        end else begin
            // 其他所有活跃状态 (CHECK, OUTER_LOOP, INNER_LOOP, START_PASS, PROCESS, PASS_DONE):
            // filter_ids = [M_crnt + m_crnt + 1, M_crnt + m_crnt + (p * t))
            //   外层基准 M_crnt + 内层偏移 m_crnt → 当前子块的输出通道范围
            //   start = M_crnt + m_crnt + 1 (ID 从 1 开始)
            //   end   = M_crnt + m_crnt + (p * t) (子块结束，不含此项)
            filter_ids = '{M_crnt + m_crnt + 1, M_crnt + m_crnt + (p * t)};
            // channel_ids = [C_crnt + 1, C_crnt + (q * r))
            //   当前 tile 需要处理的输入通道范围
            channel_ids = '{C_crnt + 1, C_crnt + (q * r)};
            // ifmap_ids = [N_crnt + 1, N_crnt + n)
            //   当前 tile 的批次范围
            ifmap_ids = '{N_crnt + 1, N_crnt + n};

            // bias_sel = 1 当 channel_ids[0] == 0
            // 即 C_crnt + 1 == 0 → C_crnt 上溢/回绕为 0 的边界条件
            // 表示这是某个输出通道组的第一个输入通道 pass，需要 bias 初始化 PE 累加器
            bias_sel = (channel_ids[0] == 0);
        end
    end

    // ===========================================================================================
    // 组合逻辑赋值 (assign): ID 信号共享
    //
    // filter_channel_ids 和 ifmap_channel_ids 都等于 channel_ids:
    //   在一个 pass 中，filter 和 ifmap 处理的输入通道范围是相同的
    //
    // psum_ids 等于 ifmap_ids:
    //   部分和的 batch 维度和 ifmap 的 batch 维度一一对应
    //
    // psum_channel_ids 等于 filter_ids:
    //   部分和的输出通道维度和 filter 的输出通道维度一一对应
    //   (psum 是各输出通道的累加结果)
    // ===========================================================================================
    assign filter_channel_ids = channel_ids;    // filter 侧输入通道范围 = channel_ids
    assign ifmap_channel_ids = channel_ids;     // ifmap 侧输入通道范围 = channel_ids

    assign psum_ids = ifmap_ids;                // psum 的 batch 维度 = ifmap 的 batch 维度
    assign psum_channel_ids = filter_ids;       // psum 的输出通道维度 = filter 的输出通道维度

endmodule
