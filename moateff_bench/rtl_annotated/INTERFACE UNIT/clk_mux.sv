// ============================================================================
// 模块名称: clk_mux (时钟复用/选通器)
// 在架构中的位置: INTERFACE UNIT - 时钟域切换（为FIFO提供wclk/rclk）
//
// 功能描述:
//   根据Direct_Back_Path信号选择link_clk或core_clk作为输出时钟。
//   通过两级寄存器同步实现无毛刺（glitch-free）时钟选通：
//   - 前向通路(DRAM->GLB): clk_out = link_clk
//   - 反向通路(GLB->DRAM): clk_out = core_clk
//   - enable=0时输出固定为0（时钟关闭，降低功耗）
//
//   选通逻辑解释:
//   - D_2_Link = (!core_r2) & (!Direct_Back_Path): core侧空闲且前向时，选link时钟
//   - D_2_core = (!link_r2) & (Direct_Back_Path): link侧空闲且反向时，选core时钟
//   - 互斥设计确保不会同时选择两个时钟源
//
//   在interface_unit中实例化两个clk_mux：
//   - U_CLK_MUX_1: 输出wclk（FIFO写时钟），Direct_Back_Path直接控制
//   - U_CLK_MUX_2: 输出rclk（FIFO读时钟），~Direct_Back_Path控制（与写侧互补）
//
// 时钟域说明:
//   - 双时钟域: link_clk（DRAM侧链路时钟）和 core_clk（加速器内核时钟）
//   - 两级同步寄存器在各自时钟域独立运行
//   - 注释提示FPGA实现建议使用BUFGMUX硬核原语替代此逻辑
// ============================================================================

module clk_mux (
    input wire 	link_clk,            // DRAM侧链路时钟输入
    input wire 	core_clk,            // 加速器内核时钟输入
	input wire  enable,              // 时钟输出使能（0=关闭时钟输出，1=允许输出）
    input wire 	Direct_Back_Path,    // 数据方向选择（0=前向DRAM->GLB，1=反向GLB->DRAM）
    input wire 	reset,               // 异步复位
    output wire clk_out             // 选通后的时钟输出
);


    // ========================================================================
    // 两级同步寄存器
    // link_r1/r2: link_clk域的二级同步链（用于D_2_Link信号）
    // core_r1/r2: core_clk域的二级同步链（用于D_2_core信号）
    // 二级同步消除跨时钟域亚稳态
    // ========================================================================
    reg link_r1, link_r2, core_r1, core_r2;

	wire D_2_Link, D_2_core;

	assign D_2_Link = (!core_r2) & (!Direct_Back_Path);   // core侧空闲 且 前向通路 -> 选link时钟
	assign D_2_core = (!link_r2) & (Direct_Back_Path);     // link侧空闲 且 反向通路 -> 选core时钟

    // ========================================================================
    // 链路时钟域: 两级寄存器同步
    // D_2_Link -> link_r1 -> link_r2 (双级同步防亚稳态)
    // ========================================================================
    always @(negedge link_clk or posedge reset) begin
        if (reset) begin
			link_r1 <= 0;
            link_r2 <= 0;
        end else begin
			link_r1 <= D_2_Link;
            link_r2 <= link_r1;      // 第二级同步寄存器
        end
    end

    // ========================================================================
    // 内核时钟域: 两级寄存器同步
    // D_2_core -> core_r1 -> core_r2
    // ========================================================================
    always @(negedge core_clk or posedge reset) begin
        if (reset) begin
			core_r1 <= 0;
            core_r2 <= 0;
        end else begin
			core_r1 <= D_2_core;
			core_r2 <= core_r1;
        end
    end

    // ========================================================================
    // 时钟门控输出
    // gated_link_clk: link_clk被link_r2门控
    // gated_core_clk: core_clk被core_r2门控
    // clk_out: enable时由选通时钟驱动，否则为0
    // ========================================================================
    wire gated_link_clk, gated_core_clk;

	assign gated_link_clk = link_clk & link_r2;    // link_r2=1时放行link_clk
	assign gated_core_clk = core_clk & core_r2;    // core_r2=1时放行core_clk

    assign clk_out = (enable) ? (gated_link_clk || gated_core_clk) : 0;

endmodule

// ========================================================================
// 注释: 在FPGA实现中建议使用BUFGMUX硬核单元替代此逻辑
// BUFGMUX是Xilinx FPGA的专用时钟选择缓冲器，可确保无毛刺时钟切换
// ========================================================================
// when using FPGA we will use BUFGMUX cell as an IP.
