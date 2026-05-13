/*
 * ===========================================================================================
 * 模块名称: eyeriss (Eyeriss 加速器顶层集成模块)
 * ===========================================================================================
 *
 * 【架构位置】
 *   本模块是 Eyeriss 卷积神经网络加速器芯片的顶层（Top-level）集成模块。
 *   处于整个 SoC 层次结构的最顶层，向下连接并协调所有子模块。
 *
 * 【功能概述】
 *   本模块集成了 Eyeriss 架构的所有核心组件，实现完整的卷积神经网络推理流程：
 *     1. 通过 SCAN_CHAIN 串行配置 CNN 形状参数（卷积层尺寸、通道数等）
 *     2. 通过 SCHEDULER 按嵌套循环顺序调度各层的执行（外层/内层循环控制）
 *     3. 通过 INTERFACE_UNIT 在片外 DRAM 与片内 GLB 之间传输数据（跨时钟域）
 *     4. 通过 GLB_UNIT (Global Line Buffer) 存储中间数据（ifmap/filter/psum/bias）
 *     5. 通过 PROCESSING_UNIT (PE 阵列 + NoC) 执行卷积和池化运算
 *     6. 通过 ReLU 阵列对输出特征图进行激活函数处理
 *
 * 【时钟域】
 *   - core_clk: 核心计算时钟域，驱动 PE 阵列、Scheduler、GLB、ReLU
 *   - link_clk: 外部接口时钟域，驱动 INTERFACE_UNIT 与 DRAM 之间的数据传输
 *
 * 【数据流向】
 *   前向（加载）:
 *     DRAM --(link_clk)--> INTERFACE_UNIT --(core_clk)--> GLB_UNIT --(core_clk)--> PROCESSING_UNIT
 *   后向（回写）:
 *     PROCESSING_UNIT --(core_clk)--> GLB_UNIT --(core_clk)--> ReLU --(core_clk)--> INTERFACE_UNIT --(link_clk)--> DRAM
 *
 * 【子模块列表】
 *   - SCAN_CHAIN:     扫描链，用于从片外串行配置 CNN 参数
 *   - SCHEDULER:      调度器，控制各层的执行顺序和循环嵌套
 *   - PROCESSING_UNIT: 处理单元（PE阵列 + 片上网络 NoC）
 *   - INTF (interface_unit): 接口单元，负责片外-片内数据传输和跨时钟域 FIFO
 *   - GLB (glb_unit): 全局行缓冲，四种片上缓冲区（ifmap/filter/psum/bias）
 *   - ReLU (relu_array): ReLU 激活函数阵列
 */

/*
 * Hint:
 * -----
 * This is the top module for the system for now
 * we need to integrate the eyeriss module with top_controller
 *
 * -----------------------------------------------------------------------------------------------
 * Eyeriss module including these modules:
 * ---------------------------------------
 *     1) Processing_Units >> Performing (Convolution & Maxpooling)
 *     2) GLBs_UNIT        >> Sharable Memory between processing unit & FIFO
 *     3) INTERFACE_UNIT   >> Interfacing between on-chip memory (GLBs) & off-chip memory (SD card)
 *     4) SCHEDULER        >>
 *     5) SCAN_CHAIN       >>
 *     6) ReLU             >>
 * ------------------------------------------------------------------------------------------------
 * Expected Inputs:
 * ----------------
 *  __ clocks, reset, configurations, enables and start signals for scheduling the layers
 *     and also the data transfer management.
 *
 * Expected Outputs:
 * -----------------
 *  __ flags (done & busy signals, enables reading from the SD card
 *             "signals from FIFO interface to DRAM" )
 *
 * Any other signals >> should be internal signals to all connect the modules with each other
 * ------------------------------------------------------------------------------------------------
 * Additional Notes:
 * -----------------
 *  __ Try to use meaningful naming convention for signals(avoid using letters)
 *  __ We need to take care of duplicated parameters
 */

module eyeriss #(
    // ===========================================================================================
    // 参数定义 - 处理单元（Processing Unit）相关参数
    // ===========================================================================================

    // DATA_WIDTH_IFMAP = 16: 输入特征图（ifmap）数据位宽
    // 每个 ifmap 像素的数据宽度，通常为 16-bit 定点数
    parameter DATA_WIDTH_IFMAP     = 16,
    // ROW_TAG_WIDTH_IFMAP = 4: ifmap 行标签位宽，用于数据流中标识行号
    parameter ROW_TAG_WIDTH_IFMAP  = 4,
    // COL_TAG_WIDTH_IFMAP = 5: ifmap 列标签位宽，用于数据流中标识列号
    parameter COL_TAG_WIDTH_IFMAP  = 5,

    // DATA_WIDTH_FILTER = 64: 滤波器（filter/weight）数据位宽
    // 一次可传输 4 个 16-bit 权重（打包传输以提高带宽）
    parameter DATA_WIDTH_FILTER    = 64,
    // ROW_TAG_WIDTH_FILTER = 4: filter 行标签位宽
    parameter ROW_TAG_WIDTH_FILTER = 4,
    // COL_TAG_WIDTH_FILTER = 4: filter 列标签位宽
    parameter COL_TAG_WIDTH_FILTER = 4,

    // DATA_WIDTH_PSUM = 64: 部分和（psum）数据位宽
    // 用于累加多个乘加结果
    parameter DATA_WIDTH_PSUM      = 64,
    // ROW_TAG_WIDTH_PSUM = 4: psum 行标签位宽
    parameter ROW_TAG_WIDTH_PSUM   = 4,
    // COL_TAG_WIDTH_PSUM = 4: psum 列标签位宽
    parameter COL_TAG_WIDTH_PSUM   = 4,

    // NUM_OF_ROWS = 12: PE 阵列行数
    // NUM_OF_COLS = 14: PE 阵列列数，共计 12×14 = 168 个处理单元
    parameter NUM_OF_ROWS = 12,
    parameter NUM_OF_COLS = 14,

    // ===========================================================================================
    // 参数定义 - PE 内部 FIFO 深度
    // ===========================================================================================

    // GIN_FIFO_DEPTH = 16: 全局输入 FIFO 深度（每个 PE 内部的 ifmap 输入 FIFO）
    parameter GIN_FIFO_DEPTH = 16,
    // GON_FIFO_DEPTH = 16: 全局输出 FIFO 深度（每个 PE 内部的 psum 输出 FIFO）
    parameter GON_FIFO_DEPTH = 16,

    // IFMAP_FIFO_DEPTH = 16: 本地 ifmap FIFO 深度（NoC 到 PE 之间的 ifmap 缓冲）
    parameter IFMAP_FIFO_DEPTH  = 16,
    // FILTER_FIFO_DEPTH = 16: 本地 filter FIFO 深度（NoC 到 PE 之间的 filter 缓冲）
    parameter FILTER_FIFO_DEPTH = 16,
    // PSUM_FIFO_DEPTH = 16: 本地 psum FIFO 深度（NoC 到 PE 之间的 psum 缓冲）
    parameter PSUM_FIFO_DEPTH   = 16,

    // ===========================================================================================
    // 参数定义 - PE 内部便签式存储器（SPAD/Scratchpad）深度
    // ===========================================================================================

    // IFMAP_SPAD_DEPTH = 12: ifmap 便签式存储器深度，每个 PE 可缓存 12 个 ifmap 数据
    parameter IFMAP_SPAD_DEPTH  = 12,
    // FILTER_SPAD_DEPTH = 224: filter 便签式存储器深度，每个 PE 可缓存 224 个权重
    // 较大深度确保滤波器权重在 PE 内尽可能重用（数据复用是 Eyeriss 节能的关键）
    parameter FILTER_SPAD_DEPTH = 224,
    // PSUM_SPAD_DEPTH = 24: psum 便签式存储器深度，每个 PE 可缓存 24 个累加值
    parameter PSUM_SPAD_DEPTH   = 24,

    // ===========================================================================================
    // 参数定义 - CNN 形状参数位宽（从扫描链配置）
    //
    // H: 输入特征图高度 (Height)
    // W: 输入特征图宽度 (Width)
    // R: 滤波器高度 (Filter Height / Kernel Rows)
    // S: 滤波器宽度 (Filter Width / Kernel Cols)
    // E: 输出特征图高度 (Output Height = ceil((H - R + 1) / stride))
    // F: 输出特征图宽度 (Output Width)
    // C: 输入通道数 (Input Channels)
    // M: 输出通道数 (Output Channels / Number of Filters)
    // N: 批次大小 (Batch Size)
    // U: 池化步长 (Pooling Stride / Upsampling factor)
    // ===========================================================================================

    parameter H_WIDTH = 8,     // ifmap 高度位宽，最大 256
    parameter W_WIDTH = 8,     // ifmap 宽度位宽，最大 256
    parameter R_WIDTH = 4,     // filter 高度位宽，最大 16 (典型值: K=3)
    parameter S_WIDTH = 4,     // filter 宽度位宽，最大 16
    parameter E_WIDTH = 6,     // 输出高度位宽，最大 64
    parameter F_WIDTH = 6,     // 输出宽度位宽，最大 64
    parameter C_WIDTH = 10,    // 输入通道数位宽，最大 1024
    parameter M_WIDTH = 10,    // 输出通道数位宽，最大 1024
    parameter N_WIDTH = 3,     // 批次大小位宽，最大 8
    parameter U_WIDTH = 3,     // 池化步长位宽，最大 8

    // ===========================================================================================
    // 参数定义 - 调度器循环展开参数位宽（Tiling Parameters）
    //
    // 由于片内存储容量有限，完整的 CNN 层被切分成多个 tile 分批次处理:
    //
    //   m: 输出通道 tile 大小（一次处理的输出通道数子块）
    //   n: 批次 tile 大小
    //   e: 输出高度 tile 大小
    //   p: 滤波器高度 tile 大小（内层循环步长因子）
    //   q: 滤波器宽度 tile 大小
    //   r: 输入通道 tile 大小
    //   t: 输出通道子 tile 大小（与 p 配合使用，p*t = 单次内循环处理的输出通道数）
    //
    // 小写字母表示 tile 级别的参数（一次处理的数据块大小），
    // 大写字母表示当前层完整的维度大小。
    // ===========================================================================================

    parameter m_WIDTH = 8,     // 通道 tile 位宽
    parameter n_WIDTH = 3,     // 批次 tile 位宽
    parameter e_WIDTH = 6,     // 输出高度 tile 位宽
    parameter p_WIDTH = 5,     // 滤波器高度 tile 位宽
    parameter q_WIDTH = 3,     // 滤波器宽度 tile 位宽
    parameter r_WIDTH = 2,     // 输入通道 tile 位宽
    parameter t_WIDTH = 3,     // 输出通道 tile 位宽（子循环）

    // ===========================================================================================
    // 参数定义 - 存储与接口相关参数
    // ===========================================================================================

    // ROW_MAJOR = 1: 行主序标志，1 表示数据按 row-major 顺序存储
    parameter ROW_MAJOR  = 1,
    // ADDR_WIDTH = 16: 地址总线宽度，可寻址 64K 个位置
    parameter ADDR_WIDTH = 16,
    // DATA_WIDTH = 16: 通用数据总线宽度（PE、GLB B 端口的数据宽度）
    parameter DATA_WIDTH = 16,

    // ===========================================================================================
    // 参数定义 - Interface Unit (接口单元) 相关
    // ===========================================================================================

    // FIFO_WIDTH = 64: FIFO 数据宽度，一次传输 4 个 16-bit 数据，匹配外部 DRAM 总线
    parameter FIFO_WIDTH = 64,
    // FIFO_DEPTH = 16: FIFO 深度，16 个 64-bit 条目（共 128 字节容量）
    parameter FIFO_DEPTH = 16,

    // ===========================================================================================
    // 参数定义 - GLB (全局行缓冲) 深度
    //
    // 四种缓冲区的深度（以单个数据条目为单位）:
    //   - IFMAP_GLB_DEPTH  = 7945:  输入特征图缓冲区，足够存放完整 ifmap tile
    //   - FILTER_GLB_DEPTH = 3872:  滤波器缓冲区，存放当前 tile 所需权重
    //   - PSUM_GLB_DEPTH   = 46656: 部分和缓冲区，存放所有输出位置的累加和（最大的一块）
    //   - BIAS_GLB_DEPTH   = 64:    偏置缓冲区，每个输出通道一个偏置项
    // ===========================================================================================

    //parameters for GLB's
    parameter IFMAP_GLB_DEPTH  = 7945,
    parameter FILTER_GLB_DEPTH = 3872,
    parameter PSUM_GLB_DEPTH   = 46656,
    parameter BIAS_GLB_DEPTH   = 64
) (
    // ===========================================================================================
    // 端口定义
    // ===========================================================================================

    // ===========================================================================================
    // 全局信号
    // ===========================================================================================

    // core_clk: 核心计算时钟
    // 方向: input, 来自顶层时钟树
    // 连接: 驱动 Scheduler、Processing Unit、GLB、ReLU、Scan Chain
    // 用途: PE 阵列及控制逻辑的主时钟域
    input  logic core_clk,

    // link_clk: 外部接口链路时钟
    // 方向: input, 来自顶层时钟树（可能与 core_clk 异步）
    // 连接: 仅驱动 interface_unit (INTF)
    // 用途: 与片外 DRAM 进行异步数据传输的独立时钟域
    input  logic link_clk,

    // reset: 全局复位信号，高有效
    // 方向: input, 来自顶层复位控制器
    // 连接: 所有子模块的复位端
    input  logic reset,

    // ===========================================================================================
    // 扫描链 (Scan Chain) 信号 —— 用于从片外串行配置 CNN 参数
    // ===========================================================================================

    // scan_en: 扫描链使能
    // 方向: input, 来自片外控制器 (如 JTAG TAP 或 SPI 主控)
    // 用途: 高有效时允许参数串行移入移位寄存器
    input  logic scan_en,

    // scan_in: 扫描链串行数据输入
    // 方向: input, 来自片外控制器
    // 用途: 逐位移入 CNN 形状参数 (H/W/R/S/E/F/C/M/N/U) 和 tiling 参数 (m/n/e/p/q/r/t)
    input  logic scan_in,

    // scan_out: 扫描链串行数据输出
    // 方向: output, 连接到片外（用于菊花链级联或回读验证）
    // 用途: 扫描链经过 SCAN_CHAIN → PROCESSING_UNIT 后的最终串行输出
    output logic scan_out,

    // ===========================================================================================
    // 控制信号 —— 整体执行流程控制
    // ===========================================================================================

    // start: 开始信号
    // 方向: input, 来自 top_controller 或外部主控
    // 用途: 上升沿触发 Eyeriss 开始执行当前配置的卷积层
    input  logic start,

    // busy: 忙碌标志
    // 方向: output, 连接到 top_controller
    // 用途: 高有效表示 Eyeriss 正在执行计算，不可接受新任务
    output logic busy,

    // done: 完成标志
    // 方向: output, 连接到 top_controller
    // 用途: 高有效表示当前层所有计算已完成，结果已回写 DRAM
    output logic done,

    // ===========================================================================================
    // Pass 相关控制信号 —— 控制单次计算通行 (Pass)
    //
    // 一次 "pass" 指 PE 阵列处理一个特定的 tile 组合：
    // 特定 ifmap tile + filter tile → 累加到对应的 psum tile
    // ===========================================================================================

    // start_pass: 启动一次计算通行
    // 方向: input, 来自外部控制逻辑（可能是 top_controller 或调度器回调）
    // 用途: 触发 PE 阵列开始当前 tile 的一次计算 pass
    input  logic start_pass,

    // pass_done: 当前 pass 完成
    // 方向: output, 连接到 scheduler
    // 用途: 通知 scheduler 当前 pass 已结束，可以进入下一 tile 调度
    output logic pass_done,

    // ofmap_dump: 输出特征图转储信号
    // 方向: output, 连接到 scheduler
    // 用途: 高有效时表示需要将完成计算的输出特征图从 psum GLB 回写到片外 DRAM
    output logic ofmap_dump,

    // dump_done: 输出转储完成
    // 方向: input, 来自接口单元（INTF）或外部控制器
    // 用途: 通知 scheduler 当前 tile 的输出数据已全部写入 DRAM，可以继续下一 tile
    input  logic dump_done,

    // ===========================================================================================
    // FIFO 接口信号 —— 片外 DRAM <-> 片内 GLB 之间的数据传输
    // ===========================================================================================

    // words_num: 待传输的 64-bit 字数
    // 方向: input, 来自 top_controller
    // 位宽: ADDR_WIDTH (16 bits)
    // 用途: 指定本次 DMA 传输的数据量（以 64-bit 字为单位，1 word = 4 个 16-bit 数据）
    input  logic [ADDR_WIDTH - 1:0] words_num,

    // transfer_done: 传输完成标志
    // 方向: output, 连接到 top_controller
    // 用途: 高有效表示当前 DMA 传输（前向或后向）已完成
    output logic                    transfer_done,

    // ===========================================================================================
    // 前向传输信号 —— DRAM → GLB (加载 ifmap / filter / bias)
    // ===========================================================================================

    // start_forward: 启动前向传输（从 DRAM 读取数据加载到 GLB）
    // 方向: input, 来自 top_controller
    // 用途: 触发 IFMAP / FILTER / BIAS 的加载流程
    input  logic                    start_forward,

    // transfer_type: 传输类型选择
    // 方向: input, 来自 top_controller
    // 位宽: 2 bits
    // 值含义:
    //   2'b00 = ifmap  传输（将输入特征图加载到 ifmap GLB）
    //   2'b01 = filter 传输（将滤波器权重加载到 filter GLB）
    //   2'b10 = bias   传输（将偏置项加载到 bias GLB）
    //   2'b11 = 保留
    // 用途: 选择本次前向传输的目标 GLB 缓冲区
    input  logic [1:0]              transfer_type,

    // re_from_dram: DRAM 读使能
    // 方向: output, 连接到外部 DRAM 控制器
    // 用途: 高有效时请求从 DRAM 读取数据
    output logic                    re_from_dram,

    // rdata_from_dram: 从 DRAM 读回的数据
    // 方向: input, 来自外部 DRAM 控制器
    // 位宽: FIFO_WIDTH (64 bits)
    // 用途: 64-bit 数据总线，一次接收 4 个 16-bit 像素/权重
    input  logic [FIFO_WIDTH - 1:0] rdata_from_dram,

    // valid_from_dram: DRAM 数据有效标志
    // 方向: input, 来自外部 DRAM 控制器
    // 用途: 高有效表示 rdata_from_dram 上的数据有效，可以接收
    input  logic                    valid_from_dram,

    // ===========================================================================================
    // 后向传输信号 —— GLB → DRAM (回写输出特征图 ofmap)
    // ===========================================================================================

    // start_backward: 启动后向传输（将输出特征图从 GLB 写回 DRAM）
    // 方向: input, 来自 top_controller
    // 用途: 触发输出特征图回写流程
    input  logic                    start_backward,

    // we_to_dram: DRAM 写使能
    // 方向: output, 连接到外部 DRAM 控制器
    // 用途: 高有效时请求向 DRAM 写入数据
    output logic                    we_to_dram,

    // wdata_to_dram: 写入 DRAM 的数据
    // 方向: output, 连接到外部 DRAM 控制器
    // 位宽: FIFO_WIDTH (64 bits)
    // 用途: 64-bit 数据总线，一次写入 4 个 16-bit 输出像素（已通过 ReLU）
    output logic [FIFO_WIDTH - 1:0] wdata_to_dram,

    // ===========================================================================================
    // 调度器输出信号 —— 标识当前 tile 的 ID 范围
    //
    // 这些信号告诉 PE 阵列和 GLB：
    //   - 当前处理的是哪个 filter 组 (filter_ids)
    //   - 当前处理的是哪个输入通道范围 (filter_channel_ids / ifmap_channel_ids)
    //   - 当前处理的是哪个 ifmap 批次 (ifmap_ids)
    //   - 部分和对应的范围和通道 (psum_ids / psum_channel_ids)
    //
    // [0:1] 表示两个元素的数组:
    //   [0] = 起始 ID (start_id)
    //   [1] = 结束 ID (end_id, 通常表示 end+1 的半开区间 [start, end))
    // ===========================================================================================

    // filter_ids: 当前 tile 的滤波器索引范围
    // 方向: output → 连接到 PE 阵列 / GLB 用于地址计算
    // 位宽: 每个 M_WIDTH(10) bits, 共 2 个元素 [start_oc, end_oc+1)
    // 含义: 当前 tile 处理的输出通道范围
    output logic [M_WIDTH - 1:0] filter_ids         [0:1],

    // filter_channel_ids: 当前滤波器对应的输入通道范围
    // 方向: output → 连接到 PE 阵列 / GLB 用于地址计算
    // 位宽: 每个 C_WIDTH(10) bits, 共 2 个元素 [start_ic, end_ic+1)
    // 注意: 与 ifmap_channel_ids 相同（同一 pass 的 filter 和 ifmap 处理相同通道范围）
    output logic [C_WIDTH - 1:0] filter_channel_ids [0:1],

    // ifmap_ids: 当前 tile 的 ifmap 批次索引范围
    // 方向: output → 连接到 PE 阵列 / GLB
    // 位宽: 每个 N_WIDTH(3) bits, 共 2 个元素 [start_batch, end_batch+1)
    output logic [N_WIDTH - 1:0] ifmap_ids         [0:1],

    // ifmap_channel_ids: 当前 ifmap 通道范围 [start_ic, end_ic+1)
    // 方向: output → 连接到 PE 阵列 / GLB
    // 位宽: 每个 C_WIDTH(10) bits, 共 2 个元素
    output logic [C_WIDTH - 1:0] ifmap_channel_ids [0:1],

    // psum_ids: 部分和的批次索引范围 [start_batch, end_batch+1)
    // 方向: output → 连接到 PE 阵列 / GLB
    // 位宽: 每个 N_WIDTH(3) bits, 共 2 个元素
    // 注意: psum 的 batch 维度与 ifmap 相同，故 psum_ids = ifmap_ids
    output logic [N_WIDTH - 1:0] psum_ids         [0:1],

    // psum_channel_ids: 部分和的输出通道索引范围 [start_oc, end_oc+1)
    // 方向: output → 连接到 PE 阵列 / GLB
    // 位宽: 每个 M_WIDTH(10) bits, 共 2 个元素
    // 注意: psum 的输出通道维度与 filter 维度相同，故 psum_channel_ids = filter_ids
    output logic [M_WIDTH - 1:0] psum_channel_ids [0:1]
);

    //--------------------------------------- Signals Declaration---------------------------------------------------\\
    // ===========================================================================================
    // 内部信号声明
    // ===========================================================================================

    // ===========================================================================================
    // 扫描链 (Scan Chain) 参数输出信号
    //
    // 扫描链将串行数据移位后并行输出这些 CNN 形状参数和 tiling 参数。
    // 这些参数在芯片配置阶段被写入，计算期间保持稳定。
    // ===========================================================================================

    // Signals for  Scan Chain
    // Mapping parameters
    logic  [H_WIDTH - 1:0] H;       // 输入特征图高度 (Height)
    logic  [W_WIDTH - 1:0] W;       // 输入特征图宽度 (Width)
    logic  [R_WIDTH - 1:0] R;       // 滤波器高度 (Kernel Height)
    logic  [S_WIDTH - 1:0] S;       // 滤波器宽度 (Kernel Width)
    logic  [E_WIDTH - 1:0] E;       // 输出特征图高度 (Output Height)
    logic  [F_WIDTH - 1:0] F;       // 输出特征图宽度 (Output Width)
    logic  [C_WIDTH - 1:0] C;       // 输入通道数 (Input Channels)
    logic  [M_WIDTH - 1:0] M;       // 输出通道数 (Output Channels)
    logic  [N_WIDTH - 1:0] N;       // 批次大小 (Batch Size)
    logic  [U_WIDTH - 1:0] U;       // 池化步长 (Pooling Stride)
    logic  [m_WIDTH - 1:0] m;       // 输出通道 tile 大小（外循环步长）
    logic  [n_WIDTH - 1:0] n;       // 批次 tile 大小
    logic  [e_WIDTH - 1:0] e;       // 输出高度 tile 大小
    logic  [p_WIDTH - 1:0] p;       // 滤波器高度 tile 大小（内循环步长因子）
    logic  [q_WIDTH - 1:0] q;       // 滤波器宽度 tile 大小
    logic  [r_WIDTH - 1:0] r;       // 输入通道 tile 大小
    logic  [t_WIDTH - 1:0] t;       // 输出通道子 tile 大小（p*t = 内循环步长）
    logic  scan_w;                   // 扫描链内部输出，连接 SCAN_CHAIN_out → PE Array scan_in

    // ===========================================================================================
    // FIFO 接口到 GLB 的信号 —— Interface Unit 与 GLB 之间的数据通路
    //
    // 前向路径（DRAM → GLB）：INTF 将 64-bit 数据拆分为 16-bit 写入 GLB 的 A 端口
    // 后向路径（GLB → DRAM）：从 GLB 的 A 端口读到 INTF，经 ReLU 后发送到 DRAM
    // ===========================================================================================

    // Signals for FIFO Interface

    // --- IFMAP GLB 写端口 (来自 FIFO 接口，64-bit 宽写入) ---
    logic                    we_from_fifo_to_ifmap_glb;        // ifmap GLB 写使能：来自 INTF，高有效时写入
    logic [FIFO_WIDTH - 1:0] wdata_from_fifo_to_ifmap_glb;    // 写入 ifmap GLB 的数据: 64-bit 打包数据 (4×16-bit)
    logic [ADDR_WIDTH - 1:0] waddr_from_fifo_to_ifmap_glb;    // 写入 ifmap GLB 的地址: 16-bit 地址

    // --- FILTER GLB 写端口 (来自 FIFO 接口) ---
    logic                    we_from_fifo_to_filter_glb;       // filter GLB 写使能
    logic [FIFO_WIDTH - 1:0] wdata_from_fifo_to_filter_glb;   // 写入 filter GLB 的数据: 64-bit (4×16-bit 权重)
    logic [ADDR_WIDTH - 1:0] waddr_from_fifo_to_filter_glb;   // 写入 filter GLB 的地址

    // --- BIAS GLB 写端口 (来自 FIFO 接口) ---
    logic                    we_from_fifo_to_bias_glb;         // bias GLB 写使能
    logic [FIFO_WIDTH - 1:0] wdata_from_fifo_to_bias_glb;     // 写入 bias GLB 的数据: 64-bit (4×16-bit 偏置)
    logic [ADDR_WIDTH - 1:0] waddr_from_fifo_to_bias_glb;     // 写入 bias GLB 的地址

    // --- PSUM GLB 读端口 (用于输出回写路径) ---
    logic                    re_from_fifo_to_psum_glb;        // psum GLB 读使能：来自 INTF，请求读取输出特征图
    logic [FIFO_WIDTH - 1:0] rdata_from_psum_glb_to_fifo;     // 从 psum GLB 读出的原始数据: 64-bit (经 A 端口读取)
    logic [FIFO_WIDTH - 1:0] relued_data_from_psum_glb_to_fifo; // 经过 ReLU 处理后的数据: 64-bit
    logic [ADDR_WIDTH - 1:0] raddr_from_fifo_to_psum_glb;     // psum GLB 读地址: 由 INTF 提供

    // ===========================================================================================
    // 处理单元 (Processing Unit / NoC) 与 GLB 之间的信号
    //
    // NoC (片上网络) 负责在 GLB 和 PE 阵列之间分发 ifmap/filter 数据
    // 并收集 PE 计算的部分和结果
    // ===========================================================================================

    // Signals for processing unit

    // --- IFMAP 读通道 (NoC 从 GLB 读取 ifmap 数据分发给 PE) ---
    logic                  ifmap_re_from_noc_to_glb;           // NoC 发出的 ifmap GLB 读使能
    logic [ADDR_WIDTH-1:0] ifmap_raddr_from_noc_to_glb;       // NoC 提供的 ifmap GLB 读地址
    logic [DATA_WIDTH-1:0] ifmap_rdata_from_glb_to_noc;       // GLB 返回给 NoC 的 ifmap 数据 (16-bit 单像素)

    // --- FILTER 读通道 (NoC 从 GLB 读取 filter 权重分发给 PE) ---
    logic                  filter_re_from_noc_to_glb;          // NoC 发出的 filter GLB 读使能
    logic [ADDR_WIDTH-1:0] filter_raddr_from_noc_to_glb;      // NoC 提供的 filter GLB 读地址
    logic [DATA_WIDTH-1:0] filter_rdata_from_glb_to_noc;      // GLB 返回给 NoC 的 filter 数据 (16-bit 单权重)

    // --- PSUM 输入读通道 (NoC 从 GLB 读取之前累加的部分和) ---
    // ipsum = input psum, 即之前 pass 累加的部分和，需要与当前 pass 的结果累加
    logic                  ipsum_re_from_noc_to_glb;           // NoC 发出的 psum GLB 读使能 (读旧部分和)
    logic [ADDR_WIDTH-1:0] ipsum_raddr_from_noc_to_glb;       // NoC 提供的 psum GLB 读地址
    logic [DATA_WIDTH-1:0] ipsum_rdata_from_glb_to_noc;       // GLB 返回给 NoC 的旧部分和数据 (16-bit)

    // --- BIAS 读通道 (NoC 从 GLB 读取偏置项，仅第一个 pass) ---
    logic [ADDR_WIDTH-1:0] bias_raddr_from_noc_to_glb;        // NoC 提供的 bias GLB 读地址
    logic [DATA_WIDTH-1:0] bias_rdata_from_glb_to_noc;        // GLB 返回给 NoC 的偏置数据 (16-bit 每通道)

    // --- PSUM 输出写通道 (NoC 将计算结果写回 GLB) ---
    // opsum = output psum, 即 PE 阵列当前 pass 计算/更新后的部分和
    logic                  opsum_we_from_noc_to_glb;           // NoC 发出的 psum GLB 写使能 (写新部分和)
    logic [ADDR_WIDTH-1:0] opsum_waddr_from_noc_to_glb;       // NoC 提供的 psum GLB 写地址
    logic [DATA_WIDTH-1:0] opsum_wdata_from_noc_to_glb;       // NoC 写入 psum GLB 的新部分和数据 (16-bit)

    // ===========================================================================================
    // 调度器 (Scheduler) 相关内部信号
    // ===========================================================================================

    // Signals for scheduler
    logic bias_sel;        // 偏置选择: 来自 scheduler
                           //   1 = 当前 pass 需要初始化 bias（第一个通道组）
                           //   0 = 当前 pass 需要累加旧的部分和
    logic start_noc;       // 启动 NoC/PE 阵列: 来自 scheduler 的 START_PASS 状态
    logic noc_done;        // NoC/PE 阵列完成: 来自 processing_unit，反馈给 scheduler

    /*--------------------------------------- Shape mapping parameters for config ---------------------------------------------------\\
        the mapping parameters, cnn shape parameters, ids, enables and local network selectors is configured serially bit by
        bit from the off chip part using scan in , scan enable and clk
    --------------------------------------------------------------------------------------------------------------------------*/
    // ===========================================================================================
    // 子模块实例化 #1: SCAN_CHAIN —— 扫描链
    // ===========================================================================================
    //
    // 【功能】
    //   扫描链 (Scan Chain) 是 Eyeriss 芯片的配置接口。
    //   在芯片启动计算之前，通过 scan_in 引脚串行移入 CNN 各层的形状参数
    //   (H, W, R, S, E, F, C, M, N, U) 和 tiling 参数 (m, n, e, p, q, r, t)。
    //
    // 【工作原理】
    //   当 scan_en=1 时，每个 core_clk 上升沿将 scan_in 移入内部移位寄存器。
    //   移位完成后（一个配置周期），所有参数并行输出到 H/W/R/... 等信号上，
    //   供 scheduler 和 processing_unit 使用。计算期间 scan_en=0，参数保持稳定。
    //
    // 【扫描链穿通路径】
    //   eyeriss.scan_in → SCAN_CHAIN → scan_w → PROCESSING → eyeriss.scan_out
    //   SCAN_CHAIN 和 PROCESSING 内部的扫描链串联成一根完整扫描链。
    //
    // 【参数位宽总计】
    //   H(8) + W(8) + R(4) + S(4) + E(6) + F(6) + C(10) + M(10) + N(3) + U(3)
    //   + m(8) + n(3) + e(6) + p(5) + q(3) + r(2) + t(3) = 92 bits
    scan_chain #(
        .H_WIDTH(H_WIDTH),
        .W_WIDTH(W_WIDTH),
        .R_WIDTH(R_WIDTH),
        .S_WIDTH(S_WIDTH),
        .E_WIDTH(E_WIDTH),
        .F_WIDTH(F_WIDTH),
        .C_WIDTH(C_WIDTH),
        .M_WIDTH(M_WIDTH),
        .N_WIDTH(N_WIDTH),
        .U_WIDTH(U_WIDTH),
        .m_WIDTH(m_WIDTH),
        .n_WIDTH(n_WIDTH),
        .e_WIDTH(e_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),
        .r_WIDTH(r_WIDTH),
        .t_WIDTH(t_WIDTH)
    ) SCAN_CHAIN (
        .clk(core_clk),          // 使用核心时钟：扫描移位与计算使用同一时钟域
        .reset(reset),           // 全局复位：复位后所有参数清零

        .scan_en(scan_en),       // 扫描使能 (来自片外)
        .scan_in(scan_in),       // 扫描输入 (来自片外)
        .scan_out(scan_w),       // 扫描输出 → 传向 PE 阵列内部扫描链的输入端

        // CNN 形状参数并行输出 → 连接到 scheduler 和 processing_unit
        .H(H),
        .W(W),
        .R(R),
        .S(S),
        .E(E),
        .F(F),
        .C(C),
        .M(M),
        .N(N),
        .U(U),
        // Tiling 参数并行输出 → 连接到 scheduler 和 processing_unit
        .m(m),
        .n(n),
        .e(e),
        .p(p),
        .q(q),
        .r(r),
        .t(t)
    );

    /*----------------------------------------- Scheduler Instantiation ---------------------------------------------------\\

    ------------------------------------------------------------------------------------------------------------------------*/
    // ===========================================================================================
    // 子模块实例化 #2: SCHEDULER —— 调度器
    // ===========================================================================================
    //
    // 【功能】
    //   调度器是 Eyeriss 的执行流程控制器，实现嵌套循环的遍历调度。
    //   Eyeriss 采用 Row-Stationary (RS) 数据流，调度器通过 FSM (有限状态机)
    //   逐级遍历多层循环：
    //
    //   外层循环 (OUTER_LOOP):
    //     遍历输出通道 M → 输出高度 E → 批次 N
    //     每完成一组 (M, E, N) tile 的完整输出通道处理，触发一次 DUMPING 回写
    //
    //   内层循环 (INNER_LOOP):
    //     遍历输出通道子块 m_crnt → 输入通道 C
    //     确保同一输出通道需要累加所有输入通道的卷积结果
    //
    //   计算过程 (PROCESS):
    //     每次 START_PASS → PROCESS 触发 PE 阵列计算一个指定 tile 的卷积
    //
    //   FSM 完整状态转移链:
    //     IDLE → CHECK → START_PASS → PROCESS → PASS_DONE → INNER_LOOP
    //          ↑                                              ↓
    //          |                        (同组 m/C 未完成) → CHECK
    //          |                        (同组 m/C 完成)   → DUMPING
    //          |                                              ↓
    //          |                        (同组 M/E/N 未完成) → OUTER_LOOP → CHECK
    //          |                        (同组 M/E/N 完成)  → DONE
    //          ←──────────────────────────────────────────────┘
    //
    // 【输出信号说明】
    //   - start_noc:          触发 PE 阵列开始计算
    //   - busy:               指示正在执行计算（PROCESS 状态）
    //   - bias_sel:           选择偏置还是旧部分和（第一批通道需要 bias 初始化）
    //   - filter_ids[0:1]:    当前 tile 的输出通道范围 [start_oc, end_oc+1)
    //   - channel_ids[0:1]:   当前 tile 的输入通道范围 [start_ic, end_ic+1)
    //   - ifmap_ids[0:1]:     当前 tile 的批次范围 [start_batch, end_batch+1)
    //
    // 【与 top_controller 的交互】
    //   - scheduler 通过 busy/done 告知 top_controller 当前层的执行状态
    //   - scheduler 输出 filter_ids/ifmap_ids 等给 GLB 地址生成和 PE 阵列投递
    //   - scheduler 接收 start_pass 和 noc_done 作为计算流程握手信号
    scheduler #(
        .E_WIDTH(E_WIDTH),
        .C_WIDTH(C_WIDTH),
        .M_WIDTH(M_WIDTH),
        .N_WIDTH(N_WIDTH),
        .m_WIDTH(m_WIDTH),
        .n_WIDTH(n_WIDTH),
        .e_WIDTH(e_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),
        .r_WIDTH(r_WIDTH),
        .t_WIDTH(t_WIDTH)
    ) SCHEDULER (
        .clk(core_clk),           // 核心时钟
        .reset(reset),            // 全局复位
        .start(start),            // 来自 top_controller: 启动当前层
        .busy(busy),              // 输出: 忙碌标志 (PROCESS 状态时为高)
        .done(done),              // 输出: 单层完成标志 (所有 tile 处理完毕)

        .start_pass(start_pass),  // 输入: 启动一次 pass (来自 top_controller)
        .pass_done(pass_done),    // 输出: 一次 pass 完成 (PASS_DONE 状态)

        .start_noc(start_noc),    // 输出: 触发 PE 阵列开始计算 (START_PASS 状态)
        .noc_done(noc_done),      // 输入: PE 阵列计算完成 (processing_unit 反馈)

        .ofmap_dump(ofmap_dump),  // 输出: 触发输出特征图回写 (DUMPING 状态)
        .dump_done(dump_done),    // 输入: 输出回写完成 (来自 INTF / top_controller)
        .bias_sel(bias_sel),      // 输出: 偏置选择 (第一批通道需要 bias 而非旧 psum 初始化)

        // CNN 形状参数 (来自扫描链)
        .E(E),
        .C(C),
        .M(M),
        .N(N),
        // Tiling 参数 (来自扫描链)
        .m(m),
        .n(n),
        .e(e),
        .p(p),
        .q(q),
        .r(r),
        .t(t),

        // 当前 tile 的 ID 范围输出 → 连接到顶层输出端口
        .filter_ids(filter_ids),
        .filter_channel_ids(filter_channel_ids),
        .ifmap_ids(ifmap_ids),
        .ifmap_channel_ids(ifmap_channel_ids),
        .psum_ids(psum_ids),
        .psum_channel_ids(psum_channel_ids)
    );

    /*--------------------------------------- Processing Unit Instantiation---------------------------------------------------\\
        The processing unit is the main module of the eyeriss architecture.
        It performs the convolution and maxpooling operations.
    --------------------------------------------------------------------------------------------------------------------------*/
    // ===========================================================================================
    // 子模块实例化 #3: PROCESSING_UNIT —— 处理单元 (PE 阵列 + 片上网络)
    // ===========================================================================================
    //
    // 【功能】
    //   处理单元是 Eyeriss 的核心计算模块，包含两大子系统：
    //
    //   1. PE 阵列 (Processing Element Array):
    //      12 行 × 14 列 = 168 个处理单元 (PE)
    //      每个 PE 内部包含：
    //        - GIN_FIFO:  全局输入 FIFO (从 NoC 接收 ifmap 数据)
    //        - GON_FIFO:  全局输出 FIFO (向 NoC 发送 psum 结果)
    //        - SPAD:      本地便签式存储器 (ifmap SPAD: 12项 / filter SPAD: 224项 / psum SPAD: 24项)
    //        - MAC 单元:  乘法器 + 累加器，执行 psum += ifmap × filter
    //      数据流: Row-Stationary (RS)
    //        - ifmap 在 PE 行之间水平复用 (广播)
    //        - filter 在 PE 列之间垂直复用 (广播)
    //        - psum 在 PE 本地驻留累加 (最小化数据传输能耗)
    //
    //   2. NoC (片上网络 Network-on-Chip):
    //      负责在 GLB 和 PE 阵列之间传输数据：
    //        - 从 GLB 读取 ifmap/filter/bias，多播到目标 PE
    //        - 收集各 PE 的 psum 结果，写回 GLB
    //
    // 【池化】 还包含 Max-Pooling 单元，对卷积输出进行降采样
    //
    // 【扫描链连接】
    //   SCAN_CHAIN.scan_w → PROCESSING.scan_in → PROCESSING.scan_out → eyeriss.scan_out
    //   扫描链穿过 scheduler 配置后继续穿过 PE 阵列（用于 PE 级别的微调配置），
    //   最终从 scan_out 输出到片外。
    processing_unit #(
        .DATA_WIDTH_IFMAP(DATA_WIDTH_IFMAP),
        .ROW_TAG_WIDTH_IFMAP(ROW_TAG_WIDTH_IFMAP),
        .COL_TAG_WIDTH_IFMAP(COL_TAG_WIDTH_IFMAP),

        .DATA_WIDTH_FILTER(DATA_WIDTH_FILTER),
        .ROW_TAG_WIDTH_FILTER(ROW_TAG_WIDTH_FILTER),
        .COL_TAG_WIDTH_FILTER(COL_TAG_WIDTH_FILTER),

        .DATA_WIDTH_PSUM(DATA_WIDTH_PSUM),
        .ROW_TAG_WIDTH_PSUM(ROW_TAG_WIDTH_PSUM),
        .COL_TAG_WIDTH_PSUM(COL_TAG_WIDTH_PSUM),

        .NUM_OF_ROWS(NUM_OF_ROWS),       // 12 行 PE
        .NUM_OF_COLS(NUM_OF_COLS),       // 14 列 PE

        .GIN_FIFO_DEPTH(GIN_FIFO_DEPTH),
        .GON_FIFO_DEPTH(GON_FIFO_DEPTH),

        .IFMAP_FIFO_DEPTH(IFMAP_FIFO_DEPTH),
        .FILTER_FIFO_DEPTH(FILTER_FIFO_DEPTH),
        .PSUM_FIFO_DEPTH(PSUM_FIFO_DEPTH),

        .IFMAP_SPAD_DEPTH(IFMAP_SPAD_DEPTH),
        .FILTER_SPAD_DEPTH(FILTER_SPAD_DEPTH),
        .PSUM_SPAD_DEPTH(PSUM_SPAD_DEPTH),

        .H_WIDTH(H_WIDTH),
        .W_WIDTH(W_WIDTH),
        .R_WIDTH(R_WIDTH),
        .S_WIDTH(S_WIDTH),
        .E_WIDTH(E_WIDTH),
        .F_WIDTH(F_WIDTH),
        .U_WIDTH(U_WIDTH),

        .m_WIDTH(m_WIDTH),
        .n_WIDTH(n_WIDTH),
        .e_WIDTH(e_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),
        .r_WIDTH(r_WIDTH),
        .t_WIDTH(t_WIDTH),

        .ROW_MAJOR(ROW_MAJOR),           // 行主序存储 (row-major)
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) PROCESSING (
        .clk(core_clk),                  // 核心时钟
        .reset(reset),                   // 全局复位
        .start(start_noc),               // 启动信号 (来自 scheduler 的 START_PASS 状态)
        .done(noc_done),                 // 完成信号 → 反馈给 scheduler (进入 PASS_DONE)

        // CNN 形状参数 (来自扫描链)
        .H(H),
        .W(W),
        .R(R),
        .S(S),
        .E(E),
        .F(F),
        .U(U),
        // Tiling 参数 (来自扫描链)
        .m(m),
        .n(n),
        .e(e),
        .p(p),
        .q(q),
        .r(r),
        .t(t),


        // ================================================================
        // IFMAP 接口 (Processing Unit ↔ GLB)
        // ================================================================
        // NoC 从 ifmap GLB 的 B 端口读取 ifmap 数据分发给 PE
        .ifmap_re_from_glb(ifmap_re_from_noc_to_glb),       // 读使能: NoC → ifmap GLB
        .ifmap_glb_addr(ifmap_raddr_from_noc_to_glb),       // 读地址: NoC → ifmap GLB
        .ifmap_from_glb(ifmap_rdata_from_glb_to_noc),       // 读数据: ifmap GLB → NoC (16-bit)

        // ================================================================
        // FILTER 接口 (Processing Unit ↔ GLB)
        // ================================================================
        // NoC 从 filter GLB 的 B 端口读取权重数据分发给 PE
        .filter_re_from_glb(filter_re_from_noc_to_glb),     // 读使能: NoC → filter GLB
        .filter_glb_addr(filter_raddr_from_noc_to_glb),     // 读地址: NoC → filter GLB
        .filter_from_glb(filter_rdata_from_glb_to_noc),     // 读数据: filter GLB → NoC (16-bit)

        // ================================================================
        // PSUM 接口 (Processing Unit ↔ GLB)
        // ================================================================
        // psum 有两条数据路径:
        //   输入 (ipsum): PE 需要读取之前累加的旧部分和用于继续累加
        //   输出 (opsum): PE 将更新后的新部分和写回 GLB
        //
        // 注意: 如果是第一个通道组的 pass (bias_sel=1),
        //        则 PE 读取 bias 而非旧 psum 作为初始值
        //       （卷积: output = bias + Σ(ifmap * filter)）

        .ipsum_re_from_glb(ipsum_re_from_noc_to_glb),       // 读使能: NoC → psum GLB (读旧部分和)
        .ipsum_glb_addr(ipsum_raddr_from_noc_to_glb),       // psum GLB 读地址
        .bias_glb_addr(bias_raddr_from_noc_to_glb),         // bias GLB 读地址
        // 数据选择: bias_sel=1 时读 bias_rdata, bias_sel=0 时读 ipsum_rdata
        .ipsum_from_glb(bias_sel ? bias_rdata_from_glb_to_noc : ipsum_rdata_from_glb_to_noc),

        .opsum_we_to_glb(opsum_we_from_noc_to_glb),         // 写使能: NoC → psum GLB (写新部分和)
        .opsum_glb_addr(opsum_waddr_from_noc_to_glb),       // psum GLB 写地址
        .opsum_to_glb(opsum_wdata_from_noc_to_glb),         // 写入数据: NoC → psum GLB (16-bit)

        // ================================================================
        // 扫描链穿通
        // ================================================================
        .scan_en(scan_en),                                   // 扫描使能
        .scan_in(scan_w),                                    // 扫描输入 (来自 SCAN_CHAIN 的 scan_w)
        .scan_out(scan_out)                                  // 最终扫描输出 (传给片外)
    );

    /*---------------------------------------  INTERFACE_UNIT  Instantiation---------------------------------------------------\\
        It is used to store the data that is being transferred between the processing unit and the GLB.
        Asynch to handle different clock domains (core_clk & link_clk).
    --------------------------------------------------------------------------------------------------------------------------*/
    // ===========================================================================================
    // 子模块实例化 #4: INTERFACE_UNIT —— 接口单元
    // ===========================================================================================
    //
    // 【功能】
    //   接口单元 (Interface Unit) 负责片外 DRAM 与片内 GLB 之间的数据传输。
    //   它是异步桥接模块，处理两个时钟域之间的数据同步：
    //     - link_clk 域:  与外部 DRAM 通信 (读/写请求、数据总线)
    //     - core_clk 域:  与内部 GLB 通信 (读写使能、地址、数据)
    //
    // 【数据传输类型】
    //   前向传输 (DRAM → GLB, 由 start_forward 触发):
    //     1. IFMAP 加载:  transfer_type = 2'b00 (ifmap 像素)
    //     2. FILTER 加载: transfer_type = 2'b01 (滤波器权重)
    //     3. BIAS 加载:   transfer_type = 2'b10 (偏置项)
    //
    //   后向传输 (GLB → DRAM, 由 start_backward 触发):
    //     4. OFMAP 回写:  输出特征图: psum GLB → ReLU → INTF → DRAM
    //
    // 【内部结构】
    //   - 异步 FIFO: 在 core_clk 和 link_clk 之间缓冲数据
    //   - 地址生成器: 为 GLB 的 A 端口生成连续写入/读取地址
    //   - 传输控制器: 管理前向/后向传输的握手协议
    //
    // 【注意】
    //   wdata_to_dram 的数据来源是经过 ReLU 处理的 relued_data，
    //   而非原始 psum 数据 (rdata_from_psum_glb_to_fifo)。
    //   这保证了回写到 DRAM 的输出特征图已经通过了激活函数。
    interface_unit #(
        .FIFO_WIDTH(FIFO_WIDTH),       // 64 bits: 与外部总线匹配
        .GLB_WIDTH(DATA_WIDTH),        // 16 bits: GLB 数据端口 (B 端口) 宽度
        .DEPTH(FIFO_DEPTH),            // 16: 异步 FIFO 深度
        .ADDR_WIDTH(ADDR_WIDTH)        // 16 bits: 地址总线宽度
    ) INTF (
        // 双时钟域: core_clk 用于 GLB 侧, link_clk 用于 DRAM 侧
        .core_clk(core_clk),           // GLB 侧时钟 (PE 计算域)
        .link_clk(link_clk),           // DRAM 侧时钟 (外部接口域)
        .reset(reset),                 // 全局复位

        // 传输参数
        .words_num(words_num),         // 待传输字数 (来自 top_controller)

        // ================================================================
        // 前向传输 (DRAM → GLB)
        // ================================================================
        .start_forward(start_forward), // 启动前向传输 (来自 top_controller)
        .ifmap_filter_bias_transfer(transfer_type), // 选择目标 GLB: 00=ifmap, 01=filter, 10=bias

        // 前向: ifmap GLB 写端口 (INTF → GLB A端口)
        .w_en_ifmap_GLB(we_from_fifo_to_ifmap_glb),
        .rdata_to_ifmap_GLB(wdata_from_fifo_to_ifmap_glb),
        .write_address_to_ifmap_GLB(waddr_from_fifo_to_ifmap_glb),

        // 前向: filter GLB 写端口 (INTF → GLB A端口)
        .w_en_filter_GLB(we_from_fifo_to_filter_glb),
        .rdata_to_filter_GLB(wdata_from_fifo_to_filter_glb),
        .write_address_to_filter_GLB(waddr_from_fifo_to_filter_glb),

        // 前向: bias GLB 写端口 (INTF → GLB A端口)
        .w_en_bias_GLB(we_from_fifo_to_bias_glb),
        .rdata_to_bias_GLB(wdata_from_fifo_to_bias_glb),
        .write_address_to_bias_GLB(waddr_from_fifo_to_bias_glb),

        // ================================================================
        // 后向传输 (GLB → DRAM)
        // ================================================================
        .start_backward(start_backward), // 启动后向传输 (来自 top_controller)
        .wdata_from_GLB(relued_data_from_psum_glb_to_fifo), // GLB 数据来源 (经 ReLU)
        .raddr_from_GLB(raddr_from_fifo_to_psum_glb),       // psum GLB 读地址

        // ================================================================
        // DRAM 侧接口 (link_clk 域)
        // ================================================================
        .r_en_DRAM(re_from_dram),           // DRAM 读使能 (输出至 DRAM 控制器)
        .valid_from_DRAM(valid_from_dram),  // DRAM 数据有效标志 (来自 DRAM 控制器)
        .wdata_from_DRAM(rdata_from_dram),  // DRAM 读回数据 (64-bit 输入)

        // ================================================================
        // DRAM 写侧 (link_clk 域) 及 GLB 读控制
        // ================================================================
        .w_en_DRAM(we_to_dram),                 // DRAM 写使能 (输出至 DRAM 控制器)
        .r_en_GLB(re_from_fifo_to_psum_glb),    // GLB 读使能 (控制从 GLB 读取)
        .rdata_to_DRAM(wdata_to_dram),          // 写入 DRAM 的数据 (64-bit)
        .transfer_done(transfer_done)            // 传输完成标志 (反馈给 top_controller)
    );

    /*--------------------------------------- GLBs Instantiation---------------------------------------------------\\
        The GLB is the shared memory between the processing unit and the FIFO.
        It is used to store the intermediate results of the processing unit and the data from the FIFO.
        The GLB is a multi-port memory that can be accessed by multiple processing units and FIFOs at the same time.
        The GLB is also used to store the weights and biases of the neural network.
        Consist of 4 buffers:
        ---------------------
        - ifmap buffer  (ifmap pixels)
        - filter buffer (filter weights)
        - psum buffer   (ipsum and opsum)
        - bias buffer   (biases of filters)
    --------------------------------------------------------------------------------------------------------------------------*/
    // ===========================================================================================
    // 子模块实例化 #5: GLB_UNIT —— 全局行缓冲单元
    // ===========================================================================================
    //
    // 【功能】
    //   全局行缓冲 (Global Line Buffer, GLB) 是 Eyeriss 架构中的片内共享存储器。
    //   它是 Processing Unit 和 Interface Unit 之间的数据桥梁：
    //     - Processing Unit (NoC) 通过 B 端口 (16-bit) 读写 ifmap/filter/psum/bias
    //     - Interface Unit (INTF) 通过 A 端口 (64-bit) 写入 ifmap/filter/bias，读取 psum
    //
    // 【四个独立缓冲区】
    //   1. IFMAP GLB (深度 7945):
    //      - 端口 A (64-bit 写):  从 INTF 接收 ifmap 数据 (4×16-bit 打包)
    //      - 端口 B (16-bit 读):  向 NoC 提供单个 ifmap 像素
    //
    //   2. FILTER GLB (深度 3872):
    //      - 端口 A (64-bit 写):  从 INTF 接收 filter 权重 (4×16-bit 打包)
    //      - 端口 B (16-bit 读):  向 NoC 提供单个权重值
    //
    //   3. BIAS GLB (深度 64):
    //      - 端口 A (64-bit 写):  从 INTF 接收 bias 值
    //      - 端口 B (16-bit 读):  向 NoC 提供偏置 (仅第一个 pass, bias_sel=1 时)
    //
    //   4. PSUM GLB (深度 46656):
    //      - 端口 A (双向, 写 16-bit / 读 64-bit):
    //        写: Processing Unit 的新部分和 → GLB (opsum_we 控制写入)
    //        读: GLB → INTF → ReLU → DRAM (输出特征图回写)
    //        地址复用: opsum_we 决定地址是 NoC 提供还是 INTF 提供
    //      - 端口 B (16-bit 读):  向 NoC 提供旧的部分和 (非 bias pass, ~bias_sel 时)
    //
    // 【端口设计理念】
    //   每个缓冲区有两个独立端口 (A 和 B)，允许同时进行：
    //     - INTF 的批量数据传输 (A 端口, 64-bit 宽, 高带宽)
    //     - Processing Unit 的逐元素访问 (B 端口, 16-bit, 低延迟)
    //   这种双端口设计实现了数据传输和计算的重叠 (乒乓操作)。
    //
    // 【地址空间概算】
    //   IFMAP:  7,945 × 16-bit  ≈ 15.5 KB
    //   FILTER: 3,872 × 16-bit  ≈ 7.6 KB
    //   PSUM:   46,656 × 16-bit ≈ 91.1 KB  (最大的一块)
    //   BIAS:   64 × 16-bit     ≈ 0.125 KB
    glb_unit #(
        .FIFO_WIDTH(FIFO_WIDTH),       // 64-bit: A 端口数据宽度 (匹配 INTF)
        .DATA_WIDTH(DATA_WIDTH),       // 16-bit: B 端口数据宽度 (匹配 NoC)
        .IFMAP_GLB_DEPTH(IFMAP_GLB_DEPTH),
        .FILTER_GLB_DEPTH(FILTER_GLB_DEPTH),
        .PSUM_GLB_DEPTH(PSUM_GLB_DEPTH),
        .BIAS_GLB_DEPTH(BIAS_GLB_DEPTH)
    ) GLB (
        .clk(core_clk),     // 单一时钟域 (核心时钟)，所有 GLB 在 core_clk 域工作

        //--------------------------------------------IFMAP GLB--------------------------------------------\\
        // port A (64 bits) — Interface Unit 写入端
        // write port
        .we_a_ifmap(we_from_fifo_to_ifmap_glb),          // 写使能: 来自 INTF
        .addr_a_ifmap(waddr_from_fifo_to_ifmap_glb),      // 写地址: 来自 INTF
        .wdata_a_ifmap(wdata_from_fifo_to_ifmap_glb),     // 写数据: 64-bit (来自 INTF)

        // port B (16 bits) — Processing Unit (NoC) 读取端
        // read port
        .re_b_ifmap(ifmap_re_from_noc_to_glb),            // 读使能: 来自 NoC
        .addr_b_ifmap(ifmap_raddr_from_noc_to_glb),       // 读地址: 来自 NoC
        .rdata_b_ifmap(ifmap_rdata_from_glb_to_noc),      // 读数据: 16-bit → 返回 NoC

        //--------------------------------------------FILTER GLB--------------------------------------------\\
        // port A (64 bits) — Interface Unit 写入端
        // write port
        .we_a_filter(we_from_fifo_to_filter_glb),          // 写使能: 来自 INTF
        .addr_a_filter(waddr_from_fifo_to_filter_glb),     // 写地址: 来自 INTF
        .wdata_a_filter(wdata_from_fifo_to_filter_glb),    // 写数据: 64-bit (来自 INTF)

        // port B (16 bits) — Processing Unit (NoC) 读取端
        // read port
        .re_b_filter(filter_re_from_noc_to_glb),           // 读使能: 来自 NoC
        .addr_b_filter(filter_raddr_from_noc_to_glb),      // 读地址: 来自 NoC
        .rdata_b_filter(filter_rdata_from_glb_to_noc),     // 读数据: 16-bit → 返回 NoC

        //--------------------------------------------BIAS GLB----------------------------------------------\\
        // port A (64 bits) — Interface Unit 写入端
        // write port
        .we_a_bias(we_from_fifo_to_bias_glb),              // 写使能: 来自 INTF
        .addr_a_bias(waddr_from_fifo_to_bias_glb),         // 写地址: 来自 INTF
        .wdata_a_bias(wdata_from_fifo_to_bias_glb),        // 写数据: 64-bit (来自 INTF)

        // port B (16 bits) — Processing Unit (NoC) 读取端
        // read port
        // 读使能条件: ipsum_re_from_noc_to_glb & bias_sel
        //   即同时满足: 1) NoC 发出 psum 读请求  2) scheduler 指示需要 bias (第一个 pass)
        // 非 bias 的 pass 不应读 bias GLB
        .re_b_bias(ipsum_re_from_noc_to_glb & bias_sel),
        .addr_b_bias(bias_raddr_from_noc_to_glb),          // 读地址: 来自 NoC
        .rdata_b_bias(bias_rdata_from_glb_to_noc),         // 读数据: 16-bit → 返回 NoC

        //--------------------------------------------PSUM GLB----------------------------------------------\\
        // port A: 双向端口
        //   写方向 (we_a_psum=1): Processing Unit → GLB (写入新部分和, 16-bit)
        //   读方向 (we_a_psum=0): GLB → Interface Unit (读出输出特征图, 64-bit)
        .we_a_psum(opsum_we_from_noc_to_glb),              // 写使能: 来自 NoC (控制 A 端口方向)
        .re_a_psum(re_from_fifo_to_psum_glb),              // 读使能: 来自 INTF (请求读输出数据)
        // 地址复用: 写时用 NoC 地址, 读时用 INTF 地址
        // 这利用了一个事实: 写和读不会同时发生（先计算后回写）
        .addr_a_psum(opsum_we_from_noc_to_glb ? opsum_waddr_from_noc_to_glb : raddr_from_fifo_to_psum_glb),
        .wdata_a_psum(opsum_wdata_from_noc_to_glb),        // 写数据: 16-bit (来自 NoC)
        .rdata_a_psum(rdata_from_psum_glb_to_fifo),        // 读数据: 64-bit → 返回 INTF (经 ReLU)

        // port B (16 bits) — Processing Unit (NoC) 读取端 (读取旧部分和)
        // read
        // 读使能条件: ipsum_re_from_noc_to_glb & (~bias_sel)
        //   即同时满足: 1) NoC 发出 psum 读请求  2) 当前不是 bias pass (后续 pass 需要累加旧 psum)
        // 如果是第一个 pass (bias_sel=1)，则不应读旧 psum (此时读 bias)
        .re_b_psum(ipsum_re_from_noc_to_glb & (~bias_sel)),
        .addr_b_psum(ipsum_raddr_from_noc_to_glb),         // 读地址: 来自 NoC
        .rdata_b_psum(ipsum_rdata_from_glb_to_noc)         // 读数据: 16-bit → 返回 NoC
    );

    /*----------------------------------------- ReLU Instantiation ---------------------------------------------------\\

    --------------------------------------------------------------------------------------------------------------------------*/
    // ===========================================================================================
    // 子模块实例化 #6: ReLU —— ReLU 激活函数阵列
    // ===========================================================================================
    //
    // 【功能】
    //   ReLU (Rectified Linear Unit) 激活函数: f(x) = max(0, x)
    //   对每个 16-bit 定点数分量独立进行非线性激活。
    //
    // 【数据路径位置】
    //   位于 psum GLB 读数据路径和 interface_unit 写数据路径之间：
    //     psum GLB (A端口) → rdata_from_psum_glb_to_fifo (64-bit)
    //                       → ReLU 阵列
    //                       → relued_data_from_psum_glb_to_fifo (64-bit)
    //                       → INTF → wdata_to_dram
    //
    //   确保回写到片外 DRAM 的输出特征图数据已经通过激活函数处理。
    //
    // 【并行度】
    //   NUM_INPUTS = FIFO_WIDTH / DATA_WIDTH = 64 / 16 = 4 路并行
    //   即 4 个独立的 16-bit ReLU，同时处理一个 64-bit 数据包中的 4 个分量。
    //
    // 【注意】
    //   此 ReLU 仅用于最终的输出回写路径 (ofmap dump)。
    //   PE 内部的部分和累加路径不经过 ReLU，
    //   因为卷积的中间累加需要保持线性（ReLU 只在最后施加）。
    relu_array #(
        .DATA_WIDTH(DATA_WIDTH),               // 16-bit: 每个分量的数据宽度
        .NUM_INPUTS(FIFO_WIDTH/DATA_WIDTH)     // 4: 并行路数 = 64 / 16 = 4
    ) ReLU (
        // 输入: 从 psum GLB 读出的原始输出特征图数据 (64-bit = 4×16-bit 打包)
        .in(rdata_from_psum_glb_to_fifo),
        // 输出: 经过 ReLU 处理的数据 (64-bit = 4×16-bit 打包)
        // 对每个 16-bit 分量: out_i = (in_i > 0) ? in_i : 0
        .out(relued_data_from_psum_glb_to_fifo)
    );

endmodule
