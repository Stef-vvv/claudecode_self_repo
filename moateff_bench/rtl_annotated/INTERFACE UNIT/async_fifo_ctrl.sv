// ============================================================================
// 模块名称: controller (接口单元主控制器 / 传输FSM)
// 在架构中的位置: INTERFACE UNIT - 顶层传输控制状态机
//
// 功能描述:
//   管理DRAM与GLB之间的数据传输流程。支持两种传输模式:
//   1. 前向传输(forward_transfer): DRAM -> GLB (ifmap/filter/bias数据加载)
//   2. 反向传输(backward_transfer): GLB -> DRAM (输出结果回写)
//
//   状态机(4态):
//   - idle(00):                等待启动信号
//   - forward_transfer(01):    DRAM -> GLB数据传输
//   - backward_transfer(11):   GLB -> DRAM数据传输
//   - wait_state(10):          等待状态（时钟切换/流水线排空/完成确认）
//
//   前向传输子模式(ifmap_filter_bias_transfer):
//   - 00: DRAM -> ifmap GLB (输入特征图)
//   - 01: DRAM -> filter GLB (权重)
//   - 10: DRAM -> bias GLB (偏置)
//
// 时钟域说明:
//   - core_clk posedge: 主状态机和大部分计数器的时钟域
//   - link_clk posedge: words_num_forward_crnt计数器的时钟域
//     (前向传输中，words_num_forward以link_clk递增，与DRAM数据有效信号同步)
//   - 输出信号为组合逻辑（always @(*)），在core_clk/link_clk域分别被采样
//
// 关键时序参数:
//   - wait_count: 等待计数器，达到6或12时触发状态转换
//     (6个周期 = 流水线排空时间，12个周期 = 反向传输完成确认时间)
// ============================================================================

module controller #(parameter ADDR_WIDTH = 20)   // 地址位宽（默认20位，支持1M寻址空间）
(
	input wire 	core_clk,                       // 内核时钟（posedge触发register）
	input wire 	link_clk,                       // 链路时钟（DRAM侧，posedge触发）
	input wire 	core_reset,                     // 内核域同步复位
	input wire 	link_reset,                     // 链路域同步复位
	input wire 	[ADDR_WIDTH-1:0] words_num,     // 需传输的总字数（基于最坏情况: conv4 filter 221184 words）
	input wire 	[1:0] ifmap_filter_bias_transfer, // 前向传输目标选择: 00=ifmap, 01=filter, 10=bias
	input wire 	start_forward,                  // 启动前向传输（DRAM->GLB）
	input wire 	valid_from_DRAM,                // DRAM数据有效标志（link_clk域）
	input wire 	start_backward,                 // 启动反向传输（GLB->DRAM，仅在conv5完成后触发一次）
	input wire 	wfull,                          // FIFO满标志
	output reg 	Direct_Back_Path,               // 数据通路方向: 0=前向(DRAM->GLB), 1=反向(GLB->DRAM)
	output reg 	[1:0] ifmap_filter,             // GLB目标选择编码（控制demuxxx和GLB写使能）
	output reg 	ifmap_bias,                     // ifmap/bias子选择: 0=bias, 1=ifmap
	output reg 	read_from_DRAM,                 // 从DRAM读取使能
	output reg 	rinc_to_GLB,                    // FIFO读到GLB的增量使能
	output reg 	read_from_GLB,                  // 从GLB读取使能
	output reg 	rinc_to_DRAM,                   // FIFO读到DRAM的增量使能
	output reg 	DRAM_w_en,                      // DRAM写使能
	output reg 	back_transfer_done,ifmap_transfer_done,filter_transfer_done,bias_transfer_done,  // 传输完成标志
	output reg 	increment,                      // GLB地址增量信号
	output reg  transfer                        // 传输激活信号（控制clk_mux的enable）
);

		// ========================================================================
		// 状态编码
		// ========================================================================
		localparam [1:0]  	idle 				   = 2'b00,
							forward_transfer       = 2'b01,
							backward_transfer      = 2'b11,
							wait_state             = 2'b10;


		// ========================================================================
		// 内部寄存器声明
		// words_num_forward: 前向传输字计数（link_clk域）
		// words_num:         反向传输字计数（core_clk域）
		// wait_count:        等待周期计数器
		// GLB_wait:          GLB反向传输等待标志
		// times:             反向传输阶段切换（0=时钟切换等待, 1=完成等待）
		// transfer_GLB:      反向传输实际开始标志
		// ========================================================================
		reg [ADDR_WIDTH-1:0] words_num_forward_crnt,words_num_forward_nxt;
		reg [ADDR_WIDTH-1:0] words_num_crnt,words_num_nxt;
		reg [3:0] wait_count_crnt, wait_count_nxt;
		reg GLB_wait_crnt,GLB_wait_nxt,times_crnt,times_nxt;
		reg ifmap_wait_crnt,ifmap_wait_nxt, filter_wait_crnt,filter_wait_nxt, bias_wait_crnt,bias_wait_nxt;
		reg transfer_GLB_crnt,transfer_GLB_nxt;


		reg [1:0] current_state, next_state;

		// ========================================================================
		// 状态寄存器: core_clk域 (posedge)
		// 管理主状态机和大部分内部计数器
		// ========================================================================
		always @(posedge core_clk, posedge core_reset)
		begin
			if (core_reset)
			begin
				current_state <= idle;
				words_num_crnt <= 0;
				wait_count_crnt <= 0;
				ifmap_wait_crnt <= 0;
				filter_wait_crnt <= 0;
				bias_wait_crnt <= 0;
				GLB_wait_crnt <= 0;
				transfer_GLB_crnt <= 0;
				times_crnt <= 0;
			end

			else
			begin
				current_state <= next_state;
				wait_count_crnt <= wait_count_nxt;
				ifmap_wait_crnt <= ifmap_wait_nxt;
				filter_wait_crnt <= filter_wait_nxt;
				bias_wait_crnt <= bias_wait_nxt;
				GLB_wait_crnt <= GLB_wait_nxt;
				words_num_crnt <= words_num_nxt;
				transfer_GLB_crnt <= transfer_GLB_nxt;
				times_crnt <= times_nxt;
			end
		end

		// ========================================================================
		// words_num_forward寄存器: link_clk域 (posedge)
		// 前向传输中以link_clk速率计数，与DRAM数据有效信号对齐
		// ========================================================================
		always @(posedge link_clk, posedge link_reset)
		begin
			if (link_reset)
			begin
				words_num_forward_crnt <= 0;
			end

			else
			begin
				words_num_forward_crnt <= words_num_forward_nxt;
			end
		end


		// ========================================================================
		// 组合逻辑: 状态转换和输出生成
		// ========================================================================
		always @(*)
		begin

		// ========================================================================
		// 输出信号默认值（防止生成锁存器latch）
		// ========================================================================
		Direct_Back_Path = 0;
		ifmap_filter = 0;
		ifmap_bias = 0;
		read_from_DRAM = 0;
		rinc_to_GLB = 0;
		read_from_GLB = 0;
		rinc_to_DRAM = 0;
		DRAM_w_en = 0;
		back_transfer_done = 0;
		ifmap_transfer_done = 0;
		filter_transfer_done = 0;
		bias_transfer_done = 0;
		increment = 0;
		transfer = 0;

		// ========================================================================
		// 内部寄存器nxt默认值（保持当前值）
		// ========================================================================
		wait_count_nxt = wait_count_crnt;
		ifmap_wait_nxt = ifmap_wait_crnt;
		filter_wait_nxt = filter_wait_crnt;
		bias_wait_nxt = bias_wait_crnt;
		GLB_wait_nxt = GLB_wait_crnt;
		times_nxt = times_crnt;
		words_num_nxt = words_num_crnt;
		words_num_forward_nxt = words_num_forward_crnt;
		transfer_GLB_nxt = transfer_GLB_crnt;

			case (current_state)
				// ========================================================================
				// IDLE状态: 等待启动信号
				// start_forward=1 -> forward_transfer状态
				// start_backward=1 -> backward_transfer状态
				// ========================================================================
				idle:
				begin
					// ... 所有输出默认为0，计数器清零
					Direct_Back_Path = 0;
					ifmap_filter = 0;
					ifmap_bias = 0;
					read_from_DRAM = 0;
					rinc_to_GLB = 0;
					read_from_GLB = 0;
					rinc_to_DRAM = 0;
					DRAM_w_en = 0;
					back_transfer_done = 0;
					ifmap_transfer_done = 0;
					filter_transfer_done = 0;
					bias_transfer_done = 0;
					words_num_nxt = 0;
					words_num_forward_nxt = 0;
					transfer = 0;

					if (start_forward)
						next_state = forward_transfer;

					else if (start_backward)
						next_state = backward_transfer;

					else
						next_state = idle;
				end


				// ========================================================================
				// FORWARD_TRANSFER状态: DRAM -> GLB数据传输
				// 根据ifmap_filter_bias_transfer选择目标GLB
				// 以link_clk速率接收DRAM数据，每收到一个有效数据words_num_forward+1
				// 达到words_num后进入wait_state
				// ========================================================================
				forward_transfer:
				begin
					transfer = 1;
					case(ifmap_filter_bias_transfer)

						// DRAM ----> ifmap GLB
						2'b00:
						begin
							increment = 1;
							Direct_Back_Path = 0;
							ifmap_filter = 2'b00;
							ifmap_bias = 1;       // ifmap_bias=1 表示选择ifmap
							read_from_DRAM = 1;
						    rinc_to_GLB = 1;

							if (words_num_forward_crnt == words_num - 1)        // 达到最大字数
							begin
								words_num_forward_nxt = 0;
								ifmap_wait_nxt = 1;    // 设置ifmap等待标志
								next_state = wait_state;
							end

							else
							begin
								if (valid_from_DRAM)
								begin
									words_num_forward_nxt = words_num_forward_crnt + 1;

								end
								else
									words_num_forward_nxt = words_num_forward_crnt;

								ifmap_wait_nxt = 0;
								next_state = forward_transfer;
							end
						end

						// DRAM ----> filter GLB
						2'b01:
						begin
							increment = 1;
							Direct_Back_Path = 0;
							ifmap_filter = 2'b10;    // ifmap_filter[1]=1 表示filter
							read_from_DRAM = 1;
							rinc_to_GLB = 1;

							if (words_num_forward_crnt == words_num - 1)
							begin
								words_num_forward_nxt = 0;
								filter_wait_nxt = 1;
								next_state = wait_state;
							end

							else
							begin
								if (valid_from_DRAM)
								begin
									words_num_forward_nxt = words_num_forward_crnt + 1;

								end
								else
									words_num_forward_nxt = words_num_forward_crnt;

								filter_wait_nxt = 0;
								next_state = forward_transfer;
							end
						end

						// DRAM ----> bias GLB
						2'b10:
						begin
							increment = 1;
							Direct_Back_Path = 0;
							ifmap_filter = 2'b01;    // ifmap_filter[1]=0, ifmap_bias=0 表示bias
							read_from_DRAM = 1;
							rinc_to_GLB = 1;

							if (words_num_forward_crnt == words_num - 1)
							begin
								words_num_forward_nxt = 0;
								bias_wait_nxt = 1;
								next_state = wait_state;
							end

							else
							begin
								if (valid_from_DRAM)
								begin
									words_num_forward_nxt = words_num_forward_crnt + 1;

								end
								else
									words_num_forward_nxt = words_num_forward_crnt;

								bias_wait_nxt = 0;
								next_state = forward_transfer;
							end
						end

						default:
						begin
							next_state = idle;
							Direct_Back_Path = 0;
							ifmap_filter = 0;
							ifmap_bias = 0;
							read_from_DRAM = 0;
							rinc_to_GLB = 0;
							increment = 0;
							words_num_forward_nxt = 0;
							bias_wait_nxt = 0;
						end
					endcase
				end


				// ========================================================================
				// BACKWARD_TRANSFER状态: GLB -> DRAM数据传输
				// 从GLB读取数据 -> FIFO写入 -> DRAM
				// 使用core_clk计数读取字数，link_clk计数写入字数
				// 完成后进入wait_state等待流水线排空
				// ========================================================================
				backward_transfer:
				begin
					transfer = 1;
					if (transfer_GLB_crnt)            // 实际传输已开始
					begin
						if (words_num_crnt == words_num - 1) // GLB读取完成 (core_clk计数)
						begin
							increment = 0;
							read_from_GLB = 0;
							if (words_num_forward_crnt == words_num - 1)    // DRAM写入完成 (link_clk计数)
							begin
								words_num_forward_nxt = 0;
								rinc_to_DRAM = 1;
								DRAM_w_en = 1;
								Direct_Back_Path = 1;
								GLB_wait_nxt = 1;
								next_state = wait_state;
							end
							else
							begin
								words_num_forward_nxt = words_num_forward_crnt + 1;
								Direct_Back_Path = 1;
								rinc_to_DRAM = 1;
								DRAM_w_en = 1;
								next_state = backward_transfer;
							end
						end

						else                              // 继续从GLB读取
						begin
							Direct_Back_Path = 1;
							read_from_GLB = 1;
							rinc_to_DRAM = 1;
							DRAM_w_en = 1;
							if (!wfull)                   // FIFO未满时才递增
							begin
								increment = 1;
								words_num_nxt = words_num_crnt + 1;
							end
							else
							begin
								increment = 0;
								words_num_nxt = words_num_crnt;
							end
							words_num_forward_nxt = words_num_forward_crnt + 1;
							next_state = backward_transfer;
						end

					end

					else               // 首次进入反向传输: 先进入wait_state进行时钟切换
					begin
						increment = 0;
						Direct_Back_Path = 1;
						GLB_wait_nxt = 1;
						times_nxt = 0;
						words_num_forward_nxt = 0;
						words_num_nxt = 0;
						next_state = wait_state;
					end
				end



				// ========================================================================
				// WAIT_STATE状态: 等待流水线排空和时钟切换稳定
				// 4个子状态:
				//   1. ifmap_wait:   等待6周期后声明ifmap_transfer_done
				//   2. filter_wait:  等待6周期后声明filter_transfer_done
				//   3. bias_wait:    等待6周期后声明bias_transfer_done
				//   4. GLB_wait:     反向传输等待（两阶段: 6周期时钟切换 + 12周期排空）
				// ========================================================================
				wait_state:
				begin
					transfer = 1;
					if (ifmap_wait_crnt)              // ===== ifmap传输完成等待 =====
					begin
						increment = 1;
						Direct_Back_Path = 0;
						ifmap_filter = 2'b00;
						read_from_DRAM = 0;

						if (wait_count_crnt == 6)     // 6周期等待完成
						begin
							wait_count_nxt = 0;
							next_state = idle;
							ifmap_wait_nxt = 0;
							ifmap_filter = 0;
							ifmap_bias = 0;
							rinc_to_GLB = 0;
							ifmap_transfer_done = 1;  // 声明ifmap传输完成
							words_num_forward_nxt = 0;
							increment = 0;
						end

						else
						begin
							wait_count_nxt = wait_count_crnt + 1;
							next_state = wait_state;
							ifmap_wait_nxt = 1;
							ifmap_bias = 1;
							rinc_to_GLB = 1;
							ifmap_transfer_done = 0;
							words_num_forward_nxt = 0;
						end
					end

					else if (filter_wait_crnt)        // ===== filter传输完成等待 =====
					begin
						increment = 1;
						Direct_Back_Path = 0;
						ifmap_filter = 2'b10;
						read_from_DRAM = 0;

						if (wait_count_crnt == 6)
						begin
							wait_count_nxt = 0;
							next_state = idle;
							filter_wait_nxt = 0;
							rinc_to_GLB = 0;
							ifmap_filter = 0;
							filter_transfer_done = 1;
							words_num_forward_nxt = 0;
							increment = 0;
						end

						else
						begin
							wait_count_nxt = wait_count_crnt + 1;
							next_state = wait_state;
							filter_wait_nxt = 1;
							rinc_to_GLB = 1;
							filter_transfer_done = 0;
							words_num_forward_nxt = 0;
						end
					end

					else if (bias_wait_crnt)          // ===== bias传输完成等待 =====
					begin
						increment = 1;
						Direct_Back_Path = 0;
						ifmap_filter = 2'b01;
						read_from_DRAM = 0;

						if (wait_count_crnt == 6)
						begin
							wait_count_nxt = 0;
							next_state = idle;
							bias_wait_nxt = 0;
							rinc_to_GLB = 0;
							ifmap_filter = 0;
							bias_transfer_done = 1;
							words_num_forward_nxt = 0;
							increment = 0;
						end

						else
						begin
							wait_count_nxt = wait_count_crnt + 1;
							next_state = wait_state;
							bias_wait_nxt = 1;
							rinc_to_GLB = 1;
							bias_transfer_done = 0;
							words_num_forward_nxt = 0;
						end
					end

					else if (GLB_wait_crnt)           // ===== GLB反向传输等待 =====
					begin
						case (times_crnt)
							1'b0:                     // 阶段0: 时钟切换等待（6周期）
							begin
								if (wait_count_crnt == 6)
								begin
									wait_count_nxt = 0;
									GLB_wait_nxt = 0;
									Direct_Back_Path = 1;
									read_from_GLB = 1;
									rinc_to_DRAM = 1;
									DRAM_w_en = 1;
									transfer_GLB_nxt = 1;   // 开始实际传输
									times_nxt = 1;
									next_state = backward_transfer;
									words_num_forward_nxt = 0;
								end

								else
								begin
									wait_count_nxt = wait_count_crnt + 1;
									GLB_wait_nxt = 1;
									Direct_Back_Path = 1;
									read_from_GLB = 0;
									rinc_to_DRAM = 0;
									DRAM_w_en = 0;
									transfer_GLB_nxt = 0;
									words_num_forward_nxt = 0;
									next_state = wait_state;
								end
							end
							1'b1:                     // 阶段1: 传输完成等待（12周期）
							begin
								if (wait_count_crnt == 12)
								begin
									increment = 0;
									wait_count_nxt = 0;
									GLB_wait_nxt = 0;
									Direct_Back_Path = 0;
									read_from_GLB = 0;
									rinc_to_DRAM = 1;
									DRAM_w_en = 1;
									transfer_GLB_nxt = 0;
									times_nxt = 0;
									back_transfer_done = 1;   // 声明反向传输完成
									next_state = idle;
								end

								else
								begin
									wait_count_nxt = wait_count_nxt + 1;
									GLB_wait_nxt = 1;
									Direct_Back_Path = 1;
									read_from_GLB = 0;
									rinc_to_DRAM = 1;
									DRAM_w_en = 1;
									transfer_GLB_nxt = 0;
									next_state = wait_state;
									increment = 0;
								end
							end
						endcase
					end

					else
					begin
						next_state = idle;
						wait_count_nxt = 0;
						ifmap_wait_nxt = 0;
						filter_wait_nxt = 0;
						bias_wait_nxt = 0;
						GLB_wait_nxt = 0;
						words_num_forward_nxt = 0;
						words_num_nxt = 0;
					end
				end

				default:
				begin
					next_state = idle;
					Direct_Back_Path = 0;
					ifmap_filter = 0;
					ifmap_bias = 0;
					read_from_DRAM = 0;
					rinc_to_GLB = 0;
					read_from_GLB = 0;
					rinc_to_DRAM = 0;
					DRAM_w_en = 0;
					back_transfer_done = 0;
					ifmap_transfer_done = 0;
					filter_transfer_done = 0;
					bias_transfer_done = 0;
					transfer = 0;
					words_num_forward_nxt = 0;
					words_num_nxt = 0;
				end
			endcase
		end


endmodule
