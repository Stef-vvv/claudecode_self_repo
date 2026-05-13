// =============================================================================
// 模块名称: sync_fifo (同步FIFO)
// 功能描述: 参数化同步FIFO, 支持读写数据宽度不同。
//           内部包含: 读写控制器、存储器、上升/下降计数器。
//           当读写宽度不同时自动处理宽度转换(打包/解包)。
// 数据流角色: 通用缓冲器 —— 被NoC控制器和GIN/GON包装器广泛使用。
// 关键参数:
//   - R_DATA_WIDTH / W_DATA_WIDTH: 读写数据宽度可不同
//   - MEM_WIDTH = min(R_DATA_WIDTH, W_DATA_WIDTH): 存储器字宽
//   - LIMIT: 宽度比的对数, 0=等宽, >0=不等宽
//   - INC_STEP / DEC_STEP: 计数器步长, 根据宽度比自动计算
// 架构:
//   - sync_fifo_up_down_counter: 维护有效数据计数
//   - sync_fifo_wr_ctrl: 写控制(写指针+满检测)
//   - sync_fifo_rd_ctrl: 读控制(读指针+空检测)
//   - sync_fifo_mem: 存储器阵列(支持宽度转换)
// =============================================================================

module sync_fifo #(
    // 读数据位宽
    parameter R_DATA_WIDTH  = 64,
    // 写数据位宽
    parameter W_DATA_WIDTH  = 16,
    // FIFO深度(以MEM_WIDTH为单位)
    parameter FIFO_DEPTH    = 256,
    // 几乎满/空阈值
    parameter ALMOST_THRESH = 2
)(
    input wire                     clk,
    input wire                     reset,
    input wire                     write_request,   // 写请求
    input wire                     read_request,    // 读请求
    input wire  [W_DATA_WIDTH-1:0] wr_data,         // 写数据

    output wire [R_DATA_WIDTH-1:0] rd_data,         // 读数据
    output wire                    full_flag,        // 满标志
    output wire                    empty_flag,       // 空标志

    output wire                    almost_full_flag,  // 几乎满
    output wire                    almost_empty_flag  // 几乎空
);

    // 地址宽度: $clog2(FIFO_DEPTH) 取对数
    localparam ADDR_WIDTH = $clog2(FIFO_DEPTH);
    // 存储器字宽: 取读写宽度的较小值
    // 原因: 以最小宽度为单位存储, 读写时通过多字访问实现宽度转换
    localparam MEM_WIDTH = (R_DATA_WIDTH > W_DATA_WIDTH) ? W_DATA_WIDTH : R_DATA_WIDTH;
    // LIMIT: 宽度比的对数, 用于指针的高位比较
    // 0: 等宽, 直接比较整个指针
    // >0: 不等宽, 高位用于空满检测, 低位用于地址
    localparam LIMIT = (R_DATA_WIDTH == W_DATA_WIDTH) ? 0 :((R_DATA_WIDTH > W_DATA_WIDTH) ? $clog2(R_DATA_WIDTH/W_DATA_WIDTH) : $clog2(W_DATA_WIDTH/R_DATA_WIDTH));

    // 读写地址和指针
    wire [ADDR_WIDTH - 1:0] wr_addr, rd_addr;
    wire [ADDR_WIDTH:0] wr_ptr, rd_ptr;      // 多1位用于空满检测
    wire wr_en, rd_en;

    // 地址 = 指针的低位 (不含LIMIT部分)
    assign wr_addr = wr_ptr [ADDR_WIDTH - 1:0];
    assign rd_addr = rd_ptr [ADDR_WIDTH - 1:0];

    // 计数器步长
    // W>R: 写1次增加 W/R (一个写产生多个读单元)
    // W<R: 写1次增加 1 (多个写填充一个读单元)
    // W=R: 步长=1
    localparam INC_STEP = (W_DATA_WIDTH == R_DATA_WIDTH) ? 1 :((W_DATA_WIDTH > R_DATA_WIDTH) ? W_DATA_WIDTH/R_DATA_WIDTH : 1);
    localparam DEC_STEP = (R_DATA_WIDTH == W_DATA_WIDTH) ? 1 :((R_DATA_WIDTH > W_DATA_WIDTH) ? R_DATA_WIDTH/W_DATA_WIDTH : 1);

    // 有效数据计数
    wire [ADDR_WIDTH:0] count;

    // 几乎满/空检测
    assign almost_empty_flag = (count <= ALMOST_THRESH);
    assign almost_full_flag  = (count >= FIFO_DEPTH - ALMOST_THRESH);

    // ---- 上升/下降计数器 ----
    // 跟踪FIFO中的有效数据量
    sync_fifo_up_down_counter #(
        .WIDTH(ADDR_WIDTH + 1),
        .INC_STEP(INC_STEP),
        .DEC_STEP(DEC_STEP)
    ) counter_inst (
        .clk(clk),
        .reset(reset),
        .inc(wr_en),        // 写使能时递增
        .dec(read_request), // 读请求时递减
        .count(count)
    );

    // ---- 读控制器 ----
    // 管理读指针, 产生读使能和空标志
    sync_fifo_rd_ctrl #(
        .R_DATA_WIDTH(R_DATA_WIDTH),
        .W_DATA_WIDTH(W_DATA_WIDTH),
        .MEM_WIDTH(MEM_WIDTH),
        .LIMIT(LIMIT),
        .FIFO_DEPTH(FIFO_DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) read_ctrl (
        .clk(clk),
        .reset(reset),

        .rd_request(read_request),
        .wr_ptr(wr_ptr[ADDR_WIDTH:LIMIT]),   // 写指针高位用于空检测
        .rd_ptr(rd_ptr),
        .rd_en(rd_en),
        .empty_flag(empty_flag)
    );

    // ---- 写控制器 ----
    // 管理写指针, 产生写使能和满标志
    sync_fifo_wr_ctrl #(
        .R_DATA_WIDTH(R_DATA_WIDTH),
        .W_DATA_WIDTH(W_DATA_WIDTH),
        .MEM_WIDTH(MEM_WIDTH),
        .LIMIT(LIMIT),
        .FIFO_DEPTH(FIFO_DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) write_ctrl (
        .clk(clk),
        .reset(reset),

        .wr_request(write_request),
        .rd_ptr(rd_ptr[ADDR_WIDTH:LIMIT]),   // 读指针高位用于满检测
        .wr_ptr(wr_ptr),
        .wr_en(wr_en),
        .full_flag(full_flag)
    );

    // ---- FIFO存储器 ----
    // 以MEM_WIDTH为单位存储, 读写时自动处理宽度转换
    sync_fifo_mem #(
        .R_DATA_WIDTH(R_DATA_WIDTH),
        .W_DATA_WIDTH(W_DATA_WIDTH),
        .MEM_WIDTH(MEM_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) fifo_mem (
        .clk(clk),
        .wr_en(wr_en),
        .rd_en(rd_en),
        .wr_data(wr_data),
        .wr_addr(wr_addr),
        .rd_addr(rd_addr),
        .rd_data(rd_data)
    );

endmodule
