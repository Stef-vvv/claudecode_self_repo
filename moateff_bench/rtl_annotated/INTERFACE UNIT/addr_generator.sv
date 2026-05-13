// ============================================================================
// 模块名称: address_generator (GLB地址生成器)
// 在架构中的位置: INTERFACE UNIT - GLB读写地址自动生成
//
// 功能描述:
//   为GLB的读写操作自动生成地址序列。有两种工作模式：
//   1. 非Direct_Back_Path（前向通路DRAM->GLB): 根据increment脉冲自增或回绕
//   2. Direct_Back_Path（反向通路GLB->DRAM): 地址持续递增
//
//   状态机(2态):
//   - IDLE(0):     等待enable且transfer后进入COUNTING，加载base_address
//   - COUNTING(1): 根据模式和条件更新地址
//
//   关键行为:
//   - 前向通路: increment每脉冲一次，地址+1；increment下降沿时重置为base_address
//     (这允许在同一个base地址上重新开始一组传输)
//   - 反向通路: increment每脉冲一次，地址+1且不重置
//   - transfer=0时返回IDLE，地址归零
//   - 输出地址 = address_nxt << 2 (左移2位，即乘以4，实现字地址到字节地址的转换)
//
// 时钟域说明:
//   - core_clk negege 触发状态寄存
//   - 组合逻辑产生nxt状态和输出
// ============================================================================

module address_generator #(parameter ADDR_WIDTH = 16)  // 地址位宽（默认16位）
(
    input wire        core_clk,           // 内核时钟（negedge触发）
    input wire        reset,              // 异步复位
	input wire        Direct_Back_Path,   // 数据通路方向: 0=前向(DRAM->GLB), 1=反向(GLB->DRAM)
    input wire        enable,             // 地址生成使能
	input wire        transfer,           // 传输进行中标志（0=停止并回到IDLE）
    input wire 		  [ADDR_WIDTH-1:0] base_address,   // 基地址（起始地址）
    input wire        increment,          // 增量脉冲（每次脉冲地址+1）
    output wire       [ADDR_WIDTH-1:0] address          // 输出地址（字节地址 = 内部字地址 << 2）
);

		// ========================================================================
		// 状态编码: 2状态FSM
		// ========================================================================
		localparam IDLE      = 1'b0;       // 空闲/等待状态
		localparam COUNTING  = 1'b1;       // 地址计数/生成状态

		reg state_crnt, state_nxt;
		reg [ADDR_WIDTH-1:0] address_crnt, address_nxt;

		// ========================================================================
		// increment下降沿检测
		// increment_falling: increment从1变为0的时刻（下降沿）
		// 用于前向通路中检测一组传输完成的边界，触发base_address重载
		// ========================================================================
		reg increment_prev;
		wire increment_falling = (increment_prev && !increment);

		// ========================================================================
		// 状态寄存器: 下降沿更新
		// 同时锁存increment_prev用于下降沿检测
		// ========================================================================
		always @(negedge core_clk or posedge reset)
		begin
			if (reset)
			begin
				state_crnt      <= IDLE;
				address_crnt    <= 0;
				increment_prev  <= 0;
			end
			else
			begin
				state_crnt      <= state_nxt;
				address_crnt    <= address_nxt;
				increment_prev  <= increment;    // 保存increment上一周期值
			end
		end

		// ========================================================================
		// 下一状态逻辑和地址生成（组合逻辑）
		// ========================================================================
		always @(*) begin
			state_nxt   = state_crnt;
			address_nxt = address_crnt;

			case (state_crnt)
				IDLE:
				begin
					// enable且transfer有效: 加载基地址，进入计数状态
					if (enable && transfer)
					begin
						address_nxt = base_address;
						state_nxt   = COUNTING;
					end
				end

				COUNTING:
				begin
					if (transfer)         // transfer保持有效，继续计数
					begin
						if (!Direct_Back_Path)  // 前向通路模式
						begin
							if (enable && increment)
							begin
								address_nxt = address_crnt + 1;   // 递增
							end
							else if (increment_falling)
							begin
								address_nxt = base_address;       // increment下降沿: 重置为基地址
							end
						end

						else               // 反向通路模式
						begin
							if (enable && increment)
							begin
								address_nxt = address_crnt + 1;   // 递增
							end
							else
							begin
								address_nxt = address_crnt;       // 保持
							end
						end
					end
					else                  // transfer=0: 停止计数，回到IDLE
					begin
						address_nxt = 0;
						state_nxt = IDLE;
					end
				end

				default: state_nxt = IDLE;
			endcase
		end

		// ========================================================================
		// 输出地址: 内部字地址左移2位 = 乘以4（字节寻址）
		// 原因: DRAM通常字节寻址，GLB内部字为32位(4字节)，需要4字节对齐
		// ========================================================================
		assign address = address_nxt << 2;

endmodule
