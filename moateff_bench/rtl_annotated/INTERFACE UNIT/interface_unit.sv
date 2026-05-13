// ============================================================================
// 模块名称: interface_unit (片外DRAM接口单元顶层)
// 在架构中的位置: INTERFACE UNIT - 顶层模块，连接DRAM与GLB
//
// 功能描述:
//   Interface Unit是Eyeriss架构中连接片外DRAM与片内GLB的桥梁。
//   负责:
//   1. 跨时钟域数据传输（DRAM的link_clk <-> 加速器的core_clk）
//   2. 双向数据通路管理（前向: DRAM->GLB, 反向: GLB->DRAM）
//   3. GLB写地址和读地址的自动生成
//   4. 传输流程的FSM控制
//
//   子模块层次:
//   - reset_sync × 2:   为core_clk和link_clk生成同步复位
//   - clk_mux × 2:      为FIFO生成wclk和rclk（方向依赖）
//   - controller:        传输状态机（FSM）
//   - async_fifo:        异步FIFO数据通路
//
//   时钟域架构:
//   - core_clk: 加速器内核时钟（GLB侧、PE阵列侧）
//   - link_clk: DRAM链路时钟（片外存储器侧）
//   - wclk:     FIFO写时钟（= link_clk前向 或 core_clk反向）
//   - rclk:     FIFO读时钟（= core_clk前向 或 link_clk反向）
//   方向切换时wclk和rclk互换!
//
//   控制信号编码 (ifmap_filter_bias_transfer):
//   - 00: 传输ifmap数据（DRAM -> ifmap GLB）
//   - 01: 传输filter权重（DRAM -> filter GLB）
//   - 10: 传输bias偏置（DRAM -> bias GLB）
//
// 传输完成标志:
//   transfer_done = for_transfer_done | back_transfer_done
//   for_transfer_done = ifmap_transfer_done | filter_transfer_done | bias_transfer_done
// ============================================================================

module interface_unit #(
    parameter FIFO_WIDTH      = 64,          // FIFO数据宽度（默认64位 = 4×16位）
              GLB_WIDTH       = 16,          // GLB单数据宽度（默认16位 Q0.8定点数）
              DEPTH           = 16,          // FIFO深度
              FIFO_ADDR_WIDTH = $clog2(DEPTH), // FIFO地址宽度（自动计算）
			  ADDR_WIDTH      = 20           // 地址线宽度（支持1M寻址空间）
)(
    input  wire                  core_clk,      // 内核时钟（GLB/PE侧）
    input  wire                  link_clk,      // DRAM链路时钟（片外侧）
    input  wire                  reset,          // 全局异步复位

    // ==================== FIFO控制 ====================
    input  wire [ADDR_WIDTH-1:0] words_num,     // 需传输的总字数

    // ==================== GLB前向通路 (DRAM -> GLB) ====================
    input  wire                  start_forward,  // 启动前向传输
    input  wire [1:0]            ifmap_filter_bias_transfer,  // 传输目标: 00=ifmap, 01=filter, 10=bias

    output wire                  w_en_ifmap_GLB,              // ifmap GLB写使能
    output wire [FIFO_WIDTH-1:0] rdata_to_ifmap_GLB,          // 发往ifmap GLB的数据（64位）
	output wire [ADDR_WIDTH-1:0] write_address_to_ifmap_GLB,  // ifmap GLB写地址

    output wire                  w_en_filter_GLB,             // filter GLB写使能
    output wire [FIFO_WIDTH-1:0] rdata_to_filter_GLB,         // 发往filter GLB的数据（64位）
    output wire [ADDR_WIDTH-1:0] write_address_to_filter_GLB, // filter GLB写地址

    output wire                  w_en_bias_GLB,               // bias GLB写使能
    output wire [FIFO_WIDTH-1:0] rdata_to_bias_GLB,           // 发往bias GLB的数据（64位）
    output wire [ADDR_WIDTH-1:0] write_address_to_bias_GLB,   // bias GLB写地址

    // ==================== GLB反向通路 (GLB -> DRAM) ====================
    input  wire                  start_backward,              // 启动反向传输
    output wire                  r_en_GLB,                    // GLB读使能
    input  wire [FIFO_WIDTH-1:0] wdata_from_GLB,              // 来自GLB的数据（64位 psum读出）
    output wire [ADDR_WIDTH-1:0] raddr_from_GLB,              // GLB读地址

    output wire                  transfer_done,               // 传输完成综合标志

    // ==================== DRAM接口 ====================
    // 前向
    output wire                  r_en_DRAM,                   // DRAM读使能
    input  wire                  valid_from_DRAM,             // DRAM数据有效标志
    output wire [FIFO_WIDTH-1:0] rdata_to_DRAM,               // 发往DRAM的数据（反向通路输出）

    // 反向
    output wire                  w_en_DRAM,                   // DRAM写使能
    input  wire [FIFO_WIDTH-1:0] wdata_from_DRAM              // 来自DRAM的数据（前向通路输入）
);

    // ========================================================================
    // 传输完成标志汇聚
    // ========================================================================
    wire       ifmap_transfer_done;
    wire       filter_transfer_done;
    wire       bias_transfer_done;
    wire       for_transfer_done;
    wire       back_transfer_done;

    // 前向传输完成: 三种GLB任一种完成即算完成
    assign for_transfer_done = ifmap_transfer_done | filter_transfer_done | bias_transfer_done;
    // 综合传输完成: 前向或反向任一完成
    assign transfer_done = for_transfer_done | back_transfer_done;

    // ========================================================================
    // 控制器-数据通路互连信号
    // ========================================================================
    wire       Direct_Back_Path;          // 数据通路方向
    wire       [1:0] ifmap_filter;         // GLB类型选择编码
    wire       ifmap_bias;                // data子类型
    wire       read_from_DRAM;            // 从DRAM读取使能
    wire       rinc_to_GLB;               // FIFO到GLB的读增量
    wire       read_from_GLB;             // 从GLB读取使能
    wire       rinc_to_DRAM;              // FIFO到DRAM的读增量
	wire       DRAM_w_en;                 // DRAM写使能
    wire       increment;                 // GLB地址增量信号
	wire 	   wclk,rclk;                 // FIFO读写时钟（由clk_mux产生）
	wire       core_reset,link_reset;     // 同步复位信号
	wire       wfull;                     // FIFO满标志
    wire       transfer;                  // 传输激活标志

    // ========================================================================
    // 基地址（当前固定为0，可扩展为参数化配置）
    // ========================================================================
    wire [ADDR_WIDTH-1:0] base_address;

    assign base_address = 0;

	// ========================================================================
	// 复位同步器: 为core_clk和link_clk各生成一个同步复位
	// ========================================================================
	reset_sync U_RST_core
	(
	.clk(core_clk),
	.reset(reset),
	.sync_reset(core_reset)              // core_clk域同步复位
	);

	reset_sync U_RST_link
	(
	.clk(link_clk),
	.reset(reset),
	.sync_reset(link_reset)              // link_clk域同步复位
	);

	// ========================================================================
	// 时钟选通器:
	// U_CLK_MUX_1: 产生wclk（写时钟）
	//   前向(DRAM->GLB): wclk = link_clk
	//   反向(GLB->DRAM): wclk = core_clk
	//   因为数据来源方提供写时钟，前向时数据来自DRAM(link_clk)，反向时来自GLB(core_clk)
	// ========================================================================
	clk_mux U_CLK_MUX_1
	(
	.link_clk(link_clk),
    .core_clk(core_clk),
    .enable(transfer),
    .Direct_Back_Path(Direct_Back_Path),
    .reset(reset),
    .clk_out(wclk)
	);

	// ========================================================================
	// U_CLK_MUX_2: 产生rclk（读时钟）
	//   Direct_Back_Path取反: 前向时rclk=core_clk, 反向时rclk=link_clk
	//   因为数据消费方提供读时钟，前向时GLB消费(core_clk)，反向时DRAM消费(link_clk)
	//   wclk和rclk始终互补
	// ========================================================================
	clk_mux U_CLK_MUX_2
	(
	.link_clk(link_clk),
    .core_clk(core_clk),
    .enable(transfer),
    .Direct_Back_Path(~Direct_Back_Path),  // 与写侧互补
    .reset(reset),
    .clk_out(rclk)
	);

    // ========================================================================
    // U0_CONTROLLER: 传输控制状态机
    // ========================================================================
    controller #(.ADDR_WIDTH(ADDR_WIDTH)) U0_CONTROLLER (
        .core_clk(core_clk),
        .link_clk(link_clk),
		.core_reset(core_reset),
		.link_reset(link_reset),
        .words_num(words_num),
        .ifmap_filter_bias_transfer(ifmap_filter_bias_transfer),
        .start_forward(start_forward),
        .valid_from_DRAM(valid_from_DRAM),
        .start_backward(start_backward),
		.wfull(wfull),
        .Direct_Back_Path(Direct_Back_Path),
        .ifmap_filter(ifmap_filter),
        .ifmap_bias(ifmap_bias),
        .read_from_DRAM(read_from_DRAM),
        .rinc_to_GLB(rinc_to_GLB),
        .read_from_GLB(read_from_GLB),
        .rinc_to_DRAM(rinc_to_DRAM),
		.DRAM_w_en(DRAM_w_en),
        .back_transfer_done(back_transfer_done),
        .ifmap_transfer_done(ifmap_transfer_done),
        .filter_transfer_done(filter_transfer_done),
        .bias_transfer_done(bias_transfer_done),
        .increment(increment),
        .transfer(transfer)
    );

    // ========================================================================
    // U1_FIFO: 异步FIFO数据通路
    // ========================================================================
    async_fifo #(.FIFO_WIDTH(FIFO_WIDTH), .GLB_WIDTH(GLB_WIDTH), .DEPTH(DEPTH), .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH), .ADDR_WIDTH(ADDR_WIDTH))U1_FIFO (
		.wclk(wclk),
		.rclk(rclk),
        .core_clk(core_clk),
        .reset(reset),
        .core_reset(core_reset),
        .Direct_Back_Path(Direct_Back_Path),
        .rinc_to_GLB(rinc_to_GLB),
        .ifmap_filter(ifmap_filter),
        .ifmap_bias(ifmap_bias),
        .rinc_to_DRAM(rinc_to_DRAM),
        .read_from_GLB(read_from_GLB),
        .read_from_DRAM(read_from_DRAM),
        .DRAM_w_en(DRAM_w_en),
        .valid_from_DRAM(valid_from_DRAM),
        .wdata_from_DRAM(wdata_from_DRAM),
        .wdata_from_GLB(wdata_from_GLB),
        .base_address(base_address),
        .increment(increment),
        .rdata_to_ifmap_GLB(rdata_to_ifmap_GLB),
        .rdata_to_filter_GLB(rdata_to_filter_GLB),
        .rdata_to_bias_GLB(rdata_to_bias_GLB),
        .rdata_to_DRAM(rdata_to_DRAM),
        .w_en_ifmap_GLB(w_en_ifmap_GLB),
        .w_en_filter_GLB(w_en_filter_GLB),
        .w_en_bias_GLB(w_en_bias_GLB),
        .w_en_DRAM(w_en_DRAM),
        .r_en_DRAM(r_en_DRAM),
        .r_en_GLB(r_en_GLB),
        .wfull(wfull),
        .raddr_from_GLB(raddr_from_GLB),
        .write_address_to_ifmap_GLB(write_address_to_ifmap_GLB),
        .write_address_to_filter_GLB(write_address_to_filter_GLB),
        .write_address_to_bias_GLB(write_address_to_bias_GLB),
		.transfer(transfer)
    );

endmodule
