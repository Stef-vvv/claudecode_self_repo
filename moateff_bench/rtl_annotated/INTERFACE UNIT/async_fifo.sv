// ============================================================================
// 模块名称: async_fifo (异步FIFO集成模块)
// 在架构中的位置: INTERFACE UNIT - DRAM/GLB之间的跨时钟域数据缓冲核心
//
// 功能描述:
//   作为DRAM与GLB之间的异步FIFO数据通路，集成以下子模块：
//   - reset_sync × 2: wclk和rclk域的复位同步
//   - muxxx × 2: 控制信号选通（valid和r_inc方向）
//   - muxx × 1: 写入数据选通（DRAM数据或GLB数据）
//   - wfull (写控制): 写指针+满标志（wclk域）
//   - rempty (读控制): 读指针+空标志（rclk域）
//   - fifo_if_mem: 存储阵列
//   - address_generator: GLB地址生成
//   - demuxx: 读数据分配（GLB方向 vs DRAM方向）
//   - demuxxx: GLB子类型分配（ifmap/filter/bias）
//
//   数据流向:
//   前向(DRAM->GLB, Direct_Back_Path=0):
//     wdata_from_DRAM -> muxx -> fifo_if_mem -> rdata -> demuxx -> demuxxx -> ifmap/filter/bias GLB
//   反向(GLB->DRAM, Direct_Back_Path=1):
//     wdata_from_GLB -> muxx -> fifo_if_mem -> rdata -> demuxx -> rdata_to_DRAM
//
// 时钟域说明:
//   - 三时钟域: wclk (写时钟), rclk (读时钟), core_clk (地址生成)
//   - wclk/rclk由clk_mux产生，随Direct_Back_Path方向变化:
//     前向: wclk=link_clk, rclk=core_clk
//     反向: wclk=core_clk, rclk=link_clk
//   - 写指针和读指针通过Gray码+两级同步在wclk/rclk之间传递
// ============================================================================

module async_fifo #(parameter FIFO_WIDTH = 64, GLB_WIDTH = 16, DEPTH = 16, FIFO_ADDR_WIDTH = $clog2 (DEPTH), ADDR_WIDTH = 20)
(
	input wire 		wclk,rclk,core_clk,         // 写时钟、读时钟、内核时钟（地址生成器用）
	input wire      reset,core_reset,           // 全局异步复位、内核域同步复位
	input wire 		Direct_Back_Path,           // 数据方向: 0=前向(DRAM->GLB), 1=反向(GLB->DRAM)
	input wire 		rinc_to_GLB,                // 读增量到GLB方向使能
	input wire 		[1:0] ifmap_filter,          // GLB类型选择: 00=ifmap, 01=bias, 10=filter
	input wire 		ifmap_bias,                 // data子类: 0=bias, 1=ifmap
	input wire 		rinc_to_DRAM,               // 读增量到DRAM方向使能
	input wire 		read_from_GLB,              // 从GLB读取使能
	input wire 		read_from_DRAM,             // 从DRAM读取使能
	input wire 		DRAM_w_en,                  // DRAM写使能
	input wire      transfer,                   // 传输进行中标志
	input wire 		valid_from_DRAM,            // DRAM数据有效标志
	input wire 		[FIFO_WIDTH-1:0] wdata_from_DRAM,     // 来自DRAM的写数据（FIFO输入端）
	input wire 		[FIFO_WIDTH-1:0] wdata_from_GLB,      // 来自GLB的写数据（FIFO输入端，反向通路用）
	input wire      [ADDR_WIDTH-1:0] base_address,        // GLB基地址
	input wire      increment,                             // GLB地址增量信号
	output wire 	[FIFO_WIDTH-1:0] rdata_to_ifmap_GLB,   // 输出到ifmap GLB的数据
	output wire     [FIFO_WIDTH-1:0] rdata_to_filter_GLB,rdata_to_bias_GLB,  // 输出到filter/bias GLB的数据
	output wire 	[FIFO_WIDTH-1:0] rdata_to_DRAM,        // 输出到DRAM的数据（反向通路）
	output reg 		w_en_ifmap_GLB,                         // ifmap GLB写使能
	output reg 		w_en_filter_GLB,                        // filter GLB写使能
	output reg 		w_en_bias_GLB,                          // bias GLB写使能
	output reg 		w_en_DRAM,                              // DRAM写使能（寄存器输出，rclk域）
	output reg 		r_en_DRAM,                              // DRAM读使能
    output reg 		r_en_GLB,                               // GLB读使能
	output reg 		wfull,                                  // FIFO满标志（对外输出）
	output reg      [ADDR_WIDTH-1:0] raddr_from_GLB,        // GLB读地址
	output reg      [ADDR_WIDTH-1:0] write_address_to_ifmap_GLB,write_address_to_filter_GLB,write_address_to_bias_GLB  // 各GLB写地址
);

		// ========================================================================
		// 内部线网声明
		// ========================================================================
		wire 	[FIFO_ADDR_WIDTH-1:0] raddrr,waddrr;     // FIFO读写地址（二进制）
		wire 	[FIFO_ADDR_WIDTH:0] rptr,wptr;            // FIFO读写指针（Gray码）
		wire 	valid;                                     // 有效写标志（选通后）
		wire 	r_inc;                                     // 读增量（选通后）
		wire    wfulll,remptyy;                            // FIFO满/空标志（内部）
		wire 	[FIFO_WIDTH-1:0] wdata;                    // 选通后的写数据
		wire 	[FIFO_WIDTH-1:0] rdata;                    // FIFO读出的原始数据
		wire 	[FIFO_WIDTH-1:0] rdata_to_GLB;             // demuxx输出到GLB方向的数据
		wire    w_en_DRAM_;                                // DRAM写使能组合逻辑值
		wire    wreset;                                    // wclk域同步复位
		wire    rreset;                                    // rclk域同步复位

		// ========================================================================
		// 复位同步器实例化
		// ========================================================================
		reset_sync U_RST_wclk
		(
		.clk(wclk),
		.reset(reset),
		.sync_reset(wreset)              // 同步到wclk域的复位
		);

		reset_sync U_RST_rclk
		(
		.clk(rclk),
		.reset(reset),
		.sync_reset(rreset)              // 同步到rclk域的复位
		);

		// ========================================================================
		// 有效写信号选通 (muxxx):
		// 前向通路: valid = valid_from_DRAM (DRAM数据有效时写入FIFO)
		// 反向通路: valid = r_en_GLB (GLB读取有效时写入FIFO)
		// ========================================================================
		muxxx U_MUXXX
		(
		.select1(Direct_Back_Path),
		.in11(r_en_GLB),
		.in00(valid_from_DRAM),
		.out1(valid)
		);

		// ========================================================================
		// FIFO写控制 (wfull): 管理写指针和满标志
		// wclk域: 使用wclk和wreset
		// ========================================================================
		wfull U_WFULL
		(
		.wclk(wclk),
		.reset(wreset),
		.winc(valid),
		.wq2_rptr(rptr),                 // 来自读侧的Gray码读指针
		.waddr(waddrr),
		.wptr(wptr),                     // 输出Gray码写指针到读侧
		.wfull(wfulll)
		);

		// ========================================================================
		// 读增量信号选通 (muxxx):
		// 前向通路: r_inc = rinc_to_GLB (读向GLB方向)
		// 反向通路: r_inc = rinc_to_DRAM (读向DRAM方向)
		// 附加条件: FIFO必须非空 (!remptyy)
		// ========================================================================
		muxxx U_MUXXX_2
		(
		.select1(Direct_Back_Path),
		.in11(rinc_to_DRAM & (!remptyy)),
		.in00(rinc_to_GLB & (!remptyy)),
		.out1(r_inc)
		);

		// ========================================================================
		// FIFO读控制 (rempty): 管理读指针和空标志
		// rclk域: 使用rclk和rreset
		// ========================================================================
		rempty U_REMPTY
		(
		.rclk(rclk),
		.reset(rreset),
		.rinc(r_inc),
		.rq2_wptr(wptr),                 // 来自写侧的Gray码写指针
		.raddr(raddrr),
		.rptr(rptr),                     // 输出Gray码读指针到写侧
		.rempty(remptyy)
		);

		// ========================================================================
		// 写数据选通 (muxx):
		// 前向通路: wdata = wdata_from_DRAM
		// 反向通路: wdata = wdata_from_GLB
		// ========================================================================
		muxx U_MUX
		(
		.select(Direct_Back_Path),
		.in1(wdata_from_GLB),
		.in0(wdata_from_DRAM),
		.out(wdata)
		);

		// ========================================================================
		// FIFO存储阵列
		// ========================================================================
		fifo_if_mem U_FIFO_MEM
		(
		.wclk(wclk),
		.reset(wreset),
		.waddr(waddrr),
		.raddr(raddrr),
		.winc(valid),
		.wfull(wfulll),
		.wdata(wdata),
		.rdata(rdata),
		.Direct_Back_Path(Direct_Back_Path)
		);

		// ========================================================================
		// GLB地址生成器
		// 前向通路: 使用r_inc触发地址递增（与GLB写入同步）
		// 反向通路: 使用read_from_GLB触发地址递增（与GLB读取同步）
		// ========================================================================
		wire address_generator_en = (~Direct_Back_Path) ? r_inc : read_from_GLB;
		wire [ADDR_WIDTH-1:0] gen_address;
		wire [ADDR_WIDTH-1:0] write_address_to_GLB;

		assign write_address_to_GLB = (~Direct_Back_Path) ? gen_address : 0;

		address_generator U_address_gen
		(
		.core_clk(core_clk),
		.reset(core_reset),
		.Direct_Back_Path(Direct_Back_Path),
		.enable(address_generator_en),
		.transfer(transfer),
		.base_address(base_address),
		.increment(increment),
		.address(gen_address)
		);

		// ========================================================================
		// FIFO读数据路由:
		// 第一级 demuxx: 根据Direct_Back_Path分到GLB或DRAM
		// ========================================================================
		demuxx U_DEMUXX
		(
		.in(rdata),
		.select(Direct_Back_Path),
		.out0(rdata_to_GLB),              // 前向: 去GLB
		.out1(rdata_to_DRAM)              // 反向: 去DRAM
		);

		// ========================================================================
		// 第二级 demuxxx: 将GLB方向数据进一步分配到ifmap/filter/bias
		// ========================================================================
		demuxxx U_DEMUXXX
		(
		.in(rdata_to_GLB),
		.select(ifmap_filter),
		.out0(rdata_to_ifmap_GLB),        // ifmap_filter=00
		.out1(rdata_to_filter_GLB),       // ifmap_filter=10
		.out2(rdata_to_bias_GLB)          // ifmap_filter=01
		);

		// ========================================================================
		// GLB写使能和DRAM控制信号生成 (组合逻辑)
		// ========================================================================
		always @(*)
		begin
			// GLB写使能: 由ifmap_filter和ifmap_bias编码译码
			// ifmap_filter=00, ifmap_bias=1 -> ifmap GLB写使能
			// ifmap_filter=10             -> filter GLB写使能
			// ifmap_filter=01, ifmap_bias=0 -> bias GLB写使能
			// 仅当FIFO非空时才有效
			w_en_ifmap_GLB = (!remptyy & (ifmap_filter == 0) & ifmap_bias);
			w_en_filter_GLB = (!remptyy & (ifmap_filter == 2'b10));
			w_en_bias_GLB = (!remptyy & (ifmap_filter == 2'b01) & ~ifmap_bias);
			r_en_DRAM = (~wfulll & read_from_DRAM);        // FIFO未满且需要读DRAM
			wfull = wfulll;                                  // 满标志输出
			raddr_from_GLB = (Direct_Back_Path) ? gen_address : 0;   // GLB读地址
			// 各GLB的写地址: 根据类型选择输出
			write_address_to_ifmap_GLB = (!ifmap_filter[1] && ifmap_bias) ? write_address_to_GLB : 0;
			write_address_to_filter_GLB = (ifmap_filter[1]) ? write_address_to_GLB : 0;
			write_address_to_bias_GLB = (!ifmap_filter[1] && !ifmap_bias) ? write_address_to_GLB : 0;
			r_en_GLB = (~wfulll & read_from_GLB);           // FIFO未满且需要读GLB
		end

		// ========================================================================
		// DRAM写使能: 组合逻辑值 -> rclk域寄存器（posedge触发）
		// 原因: w_en_DRAM输出到DRAM控制器（可能在rclk域或另一个时钟域）
		// posedge rclk寄存以确保时序稳定
		// ========================================================================
		assign w_en_DRAM_ = (~remptyy & DRAM_w_en);         // FIFO非空且DRAM写使能有效

		always @(posedge rclk, posedge rreset)
		begin
			if (rreset)
				w_en_DRAM <= 0;
			else
				w_en_DRAM <= w_en_DRAM_;
		end


endmodule
