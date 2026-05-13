// ============================================================================
// 模块名称: pe (Processing Element - 处理单元核心)
// 架构位置: PE Array 层次结构中的叶子节点
//           处理单元(processing_unit) -> PE阵列(pe_array) -> PE封装器(pe_wrapper) -> pe(本模块)
//           本模块是 PE 的数据通路核心，包含所有子模块的实例化
//
// 模块功能: 执行二维卷积的一维计算任务
//           - 管理 ifmap/filter/psum 三个便签存储器(SPAD)
//           - 执行 MAC (乘加) 操作: ifmap * filter + psum
//           - 支持零值跳过(zero-skipping)以节省功耗
//           - 支持部分和累加(accumulate)和填充(padding)
//
// 数据流:  ifmap_pixel -> ifmap_spad (写入 + 移位)
//          filter_pixel -> filter_spad (写入)
//          ipsum_pixel -> psum_spad (外部部分和输入)
//          [ifmap_spad, filter_spad] -> 乘法器 -> 截断器 -> 加法器 -> opsum_pixel -> psum_spad
// ============================================================================
module pe
#(
    // DATA_WIDTH: 单数据位宽, 默认16位 (Q0.8 定点格式)
    parameter DATA_WIDTH = 16,

    // 以下参数为各维度参数的位宽定义
    // W_WIDTH: W参数位宽 (图像宽度相关)
    parameter W_WIDTH = 8,
    // S_WIDTH: S参数位宽 (卷积核高度/ifmap行分片大小)
    parameter S_WIDTH = 5,
    // F_WIDTH: F参数位宽 (输入通道数相关)
    parameter F_WIDTH = 6,
    // U_WIDTH: U参数位宽 (步幅相关)
    parameter U_WIDTH = 3,
    // n_WIDTH: n参数位宽 (ifmap加载循环计数)
    parameter n_WIDTH = 3,
    // p_WIDTH: p参数位宽 (输出通道分片大小)
    parameter p_WIDTH = 5,
    // q_WIDTH: q参数位宽 (ifmap列分片大小)
    parameter q_WIDTH = 3,

    // V_WIDTH: V参数位宽 (padding计数, V = p[1:0] * F[1:0])
    parameter V_WIDTH = 2,

    // 便签存储器(SPAD)深度参数
    // IFMAP_SPAD_DEPTH: 输入特征图便签深度 = q * S = 3 * 4 = 12 (3列×4行窗口)
    parameter IFMAP_SPAD_DEPTH  = 12,
    // FILTER_SPAD_DEPTH: 滤波器便签深度 = p * q * S = 5 * 3 * 4 = 60 (最大值224)
    parameter FILTER_SPAD_DEPTH = 224,
    // PSUM_SPAD_DEPTH: 部分和便签深度 = p = 5 (最大值24)
    parameter PSUM_SPAD_DEPTH   = 24
) (
    // ---------- 时钟与复位 ----------
    input  clk,                               // 系统时钟 (使用下降沿)
    input  reset,                             // 异步复位 (高电平有效)
    output busy,                              // PE忙碌标志: 1=正在计算, 0=空闲(IDLE状态)

    // ---------- 配置参数输入 (传递给控制器) ----------
    input [W_WIDTH - 1:0] W,                  // 图像宽度
    input [S_WIDTH - 1:0] S,                  // 卷积核高度 / ifmap行分片大小
    input [F_WIDTH - 1:0] F,                  // 输入通道数
    input [U_WIDTH - 1:0] U,                  // 步幅
    input [n_WIDTH - 1:0] n,                  // ifmap加载循环次数
    input [p_WIDTH - 1:0] p,                  // 输出通道分片数
    input [q_WIDTH - 1:0] q,                  // ifmap列分片数

    // ---------- 输入数据接口 (ifmap) ----------
    // 输入特征图像素: 来自外部 FIFO, 写入 ifmap_spad
    input  [DATA_WIDTH - 1:0] ifmap_pixel,    // ifmap 像素数据 (16-bit Q0.8)
    input                     wr_ifmap,       // ifmap 写使能 (来自 wrapper, pop_ifmap)
    output                    ifmap_spad_full,// ifmap SPAD 满信号 (反馈给 wrapper pop控制)

    // ---------- 输入数据接口 (filter) ----------
    // 滤波器权重: 来自外部 FIFO, 写入 filter_spad
    input  [DATA_WIDTH - 1:0] filter_pixel,   // 滤波器权重数据 (16-bit Q0.8)
    input                     wr_filter,      // 滤波器写使能 (来自 wrapper, pop_filter)
    output                    filter_spad_full,// 滤波器 SPAD 满信号

    // ---------- 输入数据接口 (ipsum - 输入部分和) ----------
    // 输入部分和: 来自上方PE或外部GIN, 累加到本地psp
    input  [DATA_WIDTH - 1:0] ipsum_pixel,    // 输入部分和数据
    output                    pop_ipsum,      // 弹出输入部分和 (读取确认信号)
    input                     ipsum_fifo_empty,// 输入部分和 FIFO 空标志

    // ---------- 输出数据接口 (opsum - 输出部分和) ----------
    // 输出部分和: 本PE计算结果, 输出到下方PE或外部GON
    output [DATA_WIDTH - 1:0] opsum_pixel,    // 输出部分和数据
    output                    push_opsum,     // 输出部分和推送信号 (写入确认)
    input                     opsum_fifo_full // 输出部分和 FIFO 满标志
);

    // 地址位宽计算 (基于SPAD深度向上取2的对数)
    localparam IFMAP_ADDR_WIDTH  = $clog2(IFMAP_SPAD_DEPTH);   // ifmap SPAD 地址位宽 = 4
    localparam FILTER_ADDR_WIDTH = $clog2(FILTER_SPAD_DEPTH);  // filter SPAD 地址位宽 = 8
    localparam PSUM_ADDR_WIDTH   = $clog2(PSUM_SPAD_DEPTH);    // psum SPAD 地址位宽 = 5

    // ---------- V 参数 (padding周期数) ----------
    // V = p[1:0] * F[1:0]: 每个filter通道需要的padding周期数
    wire [V_WIDTH - 1:0] V;

    // ---------- SPAD 状态信号 ----------
    wire filter_spad_empty;  // 滤波器 SPAD 空标志: 写地址==读地址
    wire ifmap_spad_empty;   // ifmap SPAD 空标志: 写地址==读地址

    // ---------- SPAD 读出数据总线 ----------
    wire [DATA_WIDTH - 1:0] ifmap_from_spad;   // 从 ifmap SPAD 读出的像素 -> 乘法器
    wire [DATA_WIDTH - 1:0] filter_from_spad;  // 从 filter SPAD 读出的权重 -> 乘法器
    // pusm_from_spad_w: psum SPAD 原始读出; pusm_from_spad: 经转发MUX后
    wire [DATA_WIDTH - 1:0] pusm_from_spad, pusm_from_spad_w;

    // ---------- SPAD 地址总线 (三级流水线) ----------
    wire [IFMAP_ADDR_WIDTH  - 1:0] ifmap_addr;   // ifmap SPAD 读地址 = i_crnt
    wire [FILTER_ADDR_WIDTH - 1:0] filter_addr;  // filter SPAD 读地址 = i*p + j
    // psum地址三级流水: psum_addr -> psum_addr_r -> psum_addr_rr (匹配MAC流水延迟)
    wire [PSUM_ADDR_WIDTH   - 1:0] psum_addr, psum_addr_r, psum_addr_rr;

    // ---------- 加法器信号 (MAC流水第3级) ----------
    wire [DATA_WIDTH - 1:0] adder_in1;   // 加法器输入1 (乘法截断结果或外部ipsum)
    wire [DATA_WIDTH - 1:0] adder_in2;   // 加法器输入2 (来自psum SPAD的旧部分和)
    wire [DATA_WIDTH - 1:0] sum_result;  // 加法器输出: 新的部分和

    // ---------- MUX 数据通路 ----------
    // MUX1: psum数据转发 (SPAD读出 vs 加法器输出)
    // MUX2: 累加复位 (旧部分和 vs 0)
    // MUX3: 加法器输入源 (本PE乘法结果 vs 外部ipsum)
    wire [DATA_WIDTH - 1:0] mux1_out;     // MUX1 输出 (含数据转发)
    wire [DATA_WIDTH - 1:0] mux1_out_r;   // MUX1 输出打一拍 (匹配MAC流水)
    wire [DATA_WIDTH - 1:0] mux2_out;     // MUX2 输出 (含累加复位)

    // ---------- 乘法器信号 (MAC流水第1级) ----------
    wire [DATA_WIDTH - 1:0]       mul_in1;       // 乘法器输入1 = ifmap数据
    wire [DATA_WIDTH - 1:0]       mul_in2;       // 乘法器输入2 = filter权重
    wire [(2 * DATA_WIDTH) - 1:0] mul_result;    // 乘法结果 (32-bit, 16x16 -> 32)

    // ---------- 截断器信号 (MAC流水第2级) ----------
    wire [DATA_WIDTH - 1:0] truncated_result;    // 截断结果 (32-bit -> 16-bit)

    // ---------- 控制信号流水线 ----------
    // accumulate_ipsum: 累加使能, 三级流水 (_r 和 _rr 为延迟版本)
    // reset_accumulation: 累加复位, 二级流水
    wire accumulate_ipsum, accumulate_ipsum_r, accumulate_ipsum_rr;
    wire reset_accumulation, reset_accumulation_r;

    // ---------- SPAD 复位控制 ----------
    wire reset_ifmap_spad;   // ifmap SPAD 复位信号 (LOAD状态触发)
    wire reset_filter_spad;  // filter SPAD 复位信号 (LOAD最后周期触发)

    // ---------- 核心控制信号 ----------
    wire spads_empty;        // SPAD空标志组合: filter空 | ifmap空 (用于stall)
    wire shift;              // 移位使能 (STRIDE状态: ifmap SPAD左移一位实现滑动窗口)

    // ---------- SPAD 读写控制 (多级流水对齐) ----------
    wire rd_data;            // 读数据使能 (PROCESS状态)
    wire wr_psum, wr_psum_r, wr_psum_rr;    // 写psp使能 (三级流水, 对齐MAC延迟)
    wire pad, pad_r, pad_rr;                // padding标志 (三级流水)

    // ---------- SPAD 满信号内部连线 ----------
    wire ifmap_spad_full_w;   // ifmap SPAD 原始满信号 (w_addr == spad_depth)
    wire filter_spad_full_w;  // filter SPAD 原始满信号

    // ---------- 零跳过信号 ----------
    wire zero_flag;           // ifmap数据为零标志 (门控乘法使能, 节省功耗)

    // ---------- SPAD 实际深度信号 ----------
    wire [q_WIDTH + S_WIDTH - 1:0]           ifmap_spad_depth;  // = q * S
    wire [p_WIDTH + q_WIDTH + S_WIDTH - 1:0] filter_spad_depth; // = p * q * S

    // ---------- 乘法器使能 (一级流水) ----------
    wire en_mul, en_mul_r;   // en_mul = ~zero_flag & rd_data (非零且读使能时才乘)

    // ---------- 数据转发标志 ----------
    // forward: 同地址写读冲突时, 旁路SPAD直接转发加法器输出
    wire forward;

    // ========================================================================
    // zero_skipping 实例: 零值跳过缓冲区
    // 功能: 存储每个ifmap像素是否为零的标志位
    //       与ifmap_spad同步移位, 保持地址一一对应
    //       读出时 zero_flag 用于门控乘法器使能 (零值不乘, 节省功耗)
    // ========================================================================
    zero_skipping #(
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(IFMAP_SPAD_DEPTH)      // 深度与ifmap SPAD一致
    ) zero_skipping_inst (
        .clk(clk),
        .reset(reset | reset_ifmap_spad),   // 复位条件: 全局复位 或 ifmap SPAD复位

        .shift(shift),                      // 移位使能: STRIDE状态时同步移动零标志

        .w_en(wr_ifmap),                    // 写使能: 写入ifmap时同时记录零标志
        .din(ifmap_pixel),                  // 写入数据, 检查是否全零

        .r_addr(ifmap_addr),                // 读地址: 与ifmap SPAD同步读出
        .zero_flag(zero_flag)               // 零标志输出: 1=当前像素为零
    );

    // ========================================================================
    // ifmap_spad_depth = q * S
    // q: ifmap列分片数, S: 卷积核高度
    // 例如 q=3, S=4 -> 深度12: 存储3列×4行的滑动窗口数据
    // ========================================================================
    assign ifmap_spad_depth = q * S;

    // ========================================================================
    // ifmap_spad 实例: 输入特征图便签存储器
    // 功能: 存储ifmap滑动窗口数据 (q列 × S行)
    //       支持移位操作 (STRIDE状态: 窗口左移一列, 丢弃最左列)
    //       读使能条件: (~zero_flag) & rd_data (非零且读周期才读)
    // ========================================================================
    ifmap_spad #(
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(IFMAP_SPAD_DEPTH)
    ) ifmap_spad_inst (
        .clk(clk),
        .reset(reset | reset_ifmap_spad),   // 复位: 全局复位或ifmap SPAD复位

        .spad_depth(ifmap_spad_depth[IFMAP_ADDR_WIDTH - 1:0]),  // 实际深度
        .shift(shift),                      // 移位使能: 窗口左移

        .w_en(wr_ifmap),                    // 写使能
        .din(ifmap_pixel),                  // 写入数据 (ifmap像素)

        .r_addr(ifmap_addr),                // 读地址 (来自控制器: i_crnt)
        .r_en((~zero_flag) & rd_data),      // 读使能: 非零且读周期
        .dout(ifmap_from_spad),             // 读出数据 -> 乘法器输入

        .full(ifmap_spad_full_w),           // 满标志 (内部连线)
        .empty(ifmap_spad_empty)            // 空标志 (用于stall判断)
    );

    // ========================================================================
    // filter_spad_depth = p * q * S
    // p: 输出通道分片数, q: ifmap列分片, S: 卷积核高度
    // 例如 p=5, q=3, S=4 -> 深度60: 存储所有滤波器权重
    // ========================================================================
    assign filter_spad_depth = p * q * S;

    // ========================================================================
    // filter_spad 实例: 滤波器权重便签存储器
    // 功能: 存储滤波器权重数据 (无移位功能, 权重固定)
    //       满标志由写地址达到spad_depth确定
    // ========================================================================
    filter_spad  #(
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(FILTER_SPAD_DEPTH)
    ) filter_spad_inst (
        .clk(clk),
        .reset(reset | reset_filter_spad),  // 复位: 全局复位或filter SPAD复位

        .spad_depth(filter_spad_depth[FILTER_ADDR_WIDTH - 1:0]),  // 实际深度

        .w_en(wr_filter),                   // 写使能
        .din(filter_pixel),                 // 写入数据 (滤波器权重)

        .r_en((~zero_flag) & rd_data),      // 读使能: 非零且读周期
        .r_addr(filter_addr),               // 读地址 (来自控制器: i*p + j)
        .dout(filter_from_spad),            // 读出数据 -> 乘法器输入

        .full(filter_spad_full_w),          // 满标志
        .empty(filter_spad_empty)           // 空标志 (用于stall判断)
    );

    // ========================================================================
    // psum_spad 实例: 部分和便签存储器 (输出寄存器文件)
    // 功能: 存储部分和 (每个输出通道一个累加器)
    //       深度 = p (输出通道分片数)
    //       写使用 posedge clk, 读使用 negedge clk (半周期转发)
    //       写地址经过两级流水延迟 (wr_psum_rr, psum_addr_rr)
    // ========================================================================
    psum_spad #(
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(PSUM_SPAD_DEPTH)
    ) psum_spad_inst (
        .clk(clk),
        .w_en(wr_psum_rr),                  // 写使能 (两级流水延迟后)
        .din(sum_result),                   // 写入数据 (加法器输出 = 新部分和)
        .w_addr(psum_addr_rr),              // 写地址 (两级流水延迟)
        .r_addr(psum_addr),                 // 读地址 (控制器直接输出)
        .dout(pusm_from_spad_w)             // 读出数据 (写端口读, 可能为旧值)
    );

    // ========================================================================
    // V 参数计算: V = p[1:0] * F[1:0]
    // 用于控制 PADDING 状态的周期数
    // p[1:0]: 输出通道分片数低2位, F[1:0]: 输入通道数低2位
    // ========================================================================
    assign V = p[1:0] * F[1:0];

    // ========================================================================
    // pe_controller 实例: PE 有限状态机控制器
    // 功能: 控制PE的所有操作时序
    //       生成SPAD地址、读写使能、移位等控制信号
    // 状态: IDLE -> PROCESS -> ACCUMULATE -> STRIDE -> PADDING -> LOAD
    // start: ~spads_empty (两个SPAD都不为空时启动)
    // stall: spads_empty (任一SPAD为空时暂停)
    // ========================================================================
    pe_controller #(
        .S_WIDTH(S_WIDTH),
        .F_WIDTH(F_WIDTH),
        .U_WIDTH(U_WIDTH),
        .n_WIDTH(n_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),

        .IFMAP_ADDR_WIDTH(IFMAP_ADDR_WIDTH),
        .FILTER_ADDR_WIDTH(FILTER_ADDR_WIDTH),
        .PSUM_ADDR_WIDTH(PSUM_ADDR_WIDTH)
    ) pe_controller_inst (
        .clk(clk),
        .reset(reset),
        .start(~spads_empty),               // 启动条件: SPAD不空
        .stall(spads_empty),                // 暂停条件: SPAD为空
        .busy(busy),                        // 忙碌输出

        .S(S),
        .F(F),
        .U(U),
        .n(n),
        .p(p),
        .q(q),
        .V(V),

        // 控制输出: 累加复位 (PROCESS第一个周期清零旧psp)
        .reset_accumulation(reset_accumulation),
        // 累加使能 (ACCUMULATE状态, 累加外部ipsum)
        .accumulate_ipsum(accumulate_ipsum),
        // ifmap/filter SPAD复位 (LOAD状态)
        .reset_ifmap_spad(reset_ifmap_spad),
        .reset_filter_spad(reset_filter_spad),

        // SPAD 地址输出
        .ifmap_addr(ifmap_addr),                   // = i_crnt (ifmap行内位置)
        .filter_addr(filter_addr),                 // = i_crnt * p + j_crnt
        .psum_addr(psum_addr),                     // = j_crnt (输出通道索引)

        // 控制信号输出
        .shift(shift),                             // 移位使能 (STRIDE状态)
        .rd_data(rd_data),                         // 读数据使能 (PROCESS状态)
        .wr_psum(wr_psum),                         // 写psp使能 (PROCESS状态)
        .pad(pad),                                 // padding标志 (PADDING状态)

        // FIFO 状态输入
        .ipsum_fifo_empty(ipsum_fifo_empty),       // 输入psp FIFO空
        .opsum_fifo_full(opsum_fifo_full)          // 输出psp FIFO满
    );

    // ========================================================================
    // 流水线寄存器 reg1: 一级延迟 (PSUM_ADDR_WIDTH + 3 bits)
    // 打包信号: {psum_addr, wr_psum, accumulate_ipsum, pad}
    // 目的: 将这些控制信号延迟一个周期, 对齐MAC流水线的第一级延迟
    // ========================================================================
    flopr #(PSUM_ADDR_WIDTH + 3) reg1 (
        .clk(clk),
        .reset(reset),
        .d({psum_addr, wr_psum, accumulate_ipsum, pad}),
        .q({psum_addr_r, wr_psum_r, accumulate_ipsum_r, pad_r})
    );

    // ========================================================================
    // 流水线寄存器 reg2: 二级延迟 (PSUM_ADDR_WIDTH + 3 bits)
    // 目的: 再延迟一个周期, 对齐MAC流水线的第二级延迟
    // 此时 _rr 信号与 sum_result (乘法+截断+加法) 时序对齐
    // ========================================================================
    flopr #(PSUM_ADDR_WIDTH + 3) reg2 (
        .clk(clk),
        .reset(reset),
        .d({psum_addr_r, wr_psum_r, accumulate_ipsum_r, pad_r}),
        .q({psum_addr_rr, wr_psum_rr, accumulate_ipsum_rr, pad_rr})
    );

    // ========================================================================
    // forward 信号: 数据转发(旁路)标志
    // 当 psum 写地址 == psum_spad 读地址且写使能有效时,
    // 说明当前周期写入和读取的是同一个地址, 需要旁路SPAD
    // 直接将加法器输出(sum_result)转发, 避免读到SPAD中的旧值
    // ========================================================================
    assign forward = wr_psum_rr & (psum_addr_r == psum_addr_rr);

    // ========================================================================
    // MUX1: psum数据源选择 (数据转发MUX)
    // in0: pusm_from_spad_w — SPAD读出数据 (可能为旧值)
    // in1: sum_result — 加法器输出 (最新计算的部分和)
    // sel: forward — 同地址写读冲突时选择 sum_result 绕行
    // ========================================================================
    mux2x1 #(.DATA_WIDTH(DATA_WIDTH)) mux1 (
        .in0(pusm_from_spad_w),
        .in1(sum_result),
        .sel(forward),
        .out(pusm_from_spad)
    );

    // ========================================================================
    // MUX2: 累加复位MUX (清零选择)
    // in0: pusm_from_spad — 经转发处理的部分和
    // in1: 0 (全零) — 累加复位值
    // sel: reset_accumulation_r — 累加复位 (PROCESS第一周期)
    // MAC公式: psum_new = ifmap*filter + psum_old (reset时 psum_old=0)
    // ========================================================================
    mux2x1 #(.DATA_WIDTH(DATA_WIDTH)) mux2 (
        .in0(pusm_from_spad),
        .in1({DATA_WIDTH{1'b0}}),
        .sel(reset_accumulation_r),
        .out(mux1_out)
    );

    // ========================================================================
    // 乘法器输入赋值
    // mul_in1 = ifmap_from_spad: 从 ifmap SPAD 读出的像素
    // mul_in2 = filter_from_spad: 从 filter SPAD 读出的权重
    // en_mul = (~zero_flag) & (rd_data): 非零且读周期才使能乘法
    // ========================================================================
    assign mul_in1 = ifmap_from_spad;
    assign mul_in2 = filter_from_spad;
    assign en_mul = (~zero_flag) & (rd_data);

    // ========================================================================
    // multiplier 实例: 16x16 有符号乘法器 (MAC流水第1级)
    // 功能: 计算 ifmap * filter (16-bit × 16-bit -> 32-bit)
    // 时钟使能: en_mul_r (一级流水延迟后)
    // 复位或非使能时输出零
    // ========================================================================
    multiplier #(.DATA_WIDTH(DATA_WIDTH)) multiplier_inst (
        .clk(clk),
        .reset(reset),
        .enable(en_mul_r),                   // 一级流水延迟后的使能
        .x(mul_in1),                         // ifmap 像素 (16-bit Q0.8)
        .y(mul_in2),                         // filter 权重 (16-bit Q0.8)
        .product(mul_result)                 // 32-bit 乘积 (Q0.16)
    );

    // ========================================================================
    // truncator 实例: 截断器 (MAC流水第2级)
    // 功能: 将 32-bit 乘法结果截断为 16-bit
    // sel = 0: 从 bit[0] 开始取16位 (即取低16位)
    // Q0.8 * Q0.8 = Q0.16, 截取低16位得到所需 Q0.8 精度
    // ========================================================================
    truncator #(.DATA_WIDTH(DATA_WIDTH)) truncator_inst (
        .sel(5'b0),                          // 选择起始位=0, 取低16位
        .in(mul_result),                     // 32-bit 输入
        .out(truncated_result)               // 16-bit 截断输出
    );

    // ========================================================================
    // 流水线寄存器 reg3: 一级延迟 (DATA_WIDTH + 2 bits)
    // 打包: {mux1_out, en_mul, reset_accumulation}
    // 目的: 对齐 mux1_out 与 truncated_result 的时序
    //       (mux1_out从SPAD路径延迟大于乘法+截断路径, 需要额外对齐)
    // ========================================================================
    flopr #(DATA_WIDTH + 2) reg3 (
        .clk(clk),
        .reset(reset),
        .d({mux1_out, en_mul, reset_accumulation}),
        .q({mux1_out_r, en_mul_r, reset_accumulation_r})
    );

    // ========================================================================
    // MUX3: 加法器输入源选择
    // in0: truncated_result — 本PE的乘法截断结果
    // in1: ipsum_pixel — 来自其他PE的部分和 (用于累加)
    // sel: accumulate_ipsum_rr — 累加使能 (两级流水)
    // 正常模式: mux2_out = truncated_result (本PE结果)
    // 累加模式: mux2_out = ipsum_pixel (外部psum输入)
    // ========================================================================
    mux2x1 #(.DATA_WIDTH(DATA_WIDTH)) mux3 (
        .in0(truncated_result),
        .in1(ipsum_pixel),
        .sel(accumulate_ipsum_rr),
        .out(mux2_out)
    );

    // ========================================================================
    // 加法器输入连接
    // adder_in1 = mux2_out: 本PE结果(或外部ipsum)
    // adder_in2 = mux1_out_r: 旧部分和 (经流水延迟)
    // 新部分和 = 增量 + 旧部分和
    // ========================================================================
    assign adder_in1   = mux2_out;
    assign adder_in2   = mux1_out_r;

    // ========================================================================
    // opsum_pixel 输出: 部分和输出数据
    // PADDING状态(pad_rr=1): 输出0 (填充零值)
    // 正常状态: 输出 sum_result (新的部分和)
    // ========================================================================
    assign opsum_pixel = (pad_rr == 1'b1) ? 'b0 : sum_result;

    // ========================================================================
    // adder 实例: 组合逻辑加法器 (MAC流水第3级, 最后一级)
    // sum = adder_in1 + adder_in2 (新部分和 = 增量贡献 + 旧累加值)
    // ========================================================================
    adder #(.DATA_WIDTH(DATA_WIDTH)) adder_inst (
			.x(adder_in1),
			.y(adder_in2),
			.sum(sum_result)
		);

    // ========================================================================
    // 组合逻辑: SPAD 状态与控制
    // spads_empty: 任一SPAD为空则需要暂停 (stall=1)
    // ifmap_spad_full: 原始满标志 OR 移位中 OR 复位中 (禁止外部写入)
    // filter_spad_full: 原始满标志 OR 复位中
    // pop_ipsum: 累加或padding时从输入FIFO弹出 (确认读取)
    // push_opsum: 累加或padding时将结果推入输出FIFO (确认写入)
    // ========================================================================
    assign spads_empty = filter_spad_empty | ifmap_spad_empty;
    assign ifmap_spad_full = ifmap_spad_full_w | shift | reset_ifmap_spad;
    assign filter_spad_full = filter_spad_full_w | reset_filter_spad;

    assign pop_ipsum  = accumulate_ipsum_rr | pad_rr;
    assign push_opsum = accumulate_ipsum_rr | pad_rr;

endmodule
