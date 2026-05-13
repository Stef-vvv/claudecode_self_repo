// ============================================================================
// 模块名称: clk_gating (时钟门控单元)
// 架构位置: pe_wrapper.v 内部的时钟控制子模块
//           pe_wrapper -> clk_gating(本模块)
//
// 模块功能: 使用 latch-based 时钟门控技术控制 PE 时钟
//           enable=1: gated_clk = clk (时钟正常通过)
//           enable=0: gated_clk = 0 (时钟停止翻转)
//           关闭未使用的 PE 时钟以节省动态功耗
//
// 工作原理 (latch-based clock gating, 无毛刺设计):
//   1. 低电平锁存器: 当 clk=0 时, latch_en <= enable
//      (在时钟低电平期间透明采样 enable, 存入 latch_en)
//   2. AND 门: gated_clk = clk & latch_en
//      (当时钟高且 latch_en=1 时输出1, 否则输出0)
//
//   此设计避免了 glitch (毛刺):
//   - enable 只在 clk=0 时被锁存器采样
//   - clk=1 期间 latch_en 保持稳定 (锁存器锁存)
//   - gated_clk 不会在时钟高电平期间因 enable 变化而产生毛刺
//   - gated_clk 的上升沿与 clk 上升沿完美对齐
//
// 在 PE Array 中的使用:
//   - enable 通过扫描链 (scan chain) 配置
//   - 未使用的 PE 设置 enable=0, 其内部所有寄存器和FIFO停止翻转
//   - 大幅降低整个阵列的动态功耗
// ============================================================================
module clk_gating (
    input  enable,       // 时钟使能: 1=打开时钟, 0=关闭时钟
    input  clk,          // 原始时钟输入
    output gated_clk     // 门控后时钟输出 (给 PE 及所有内部 FIFO)
);

    // 内部锁存器: 存储 enable 状态
    // 在 clk=0 时透明, 在 clk=1 时锁存
    reg latch_en;

    // =======================================================================
    // 电平敏感锁存器 (Level-sensitive latch)
    // always @(clk or enable): clk 或 enable 变化时触发
    // if (!clk): 当时钟低电平时, 锁存器透明, latch_en <= enable
    //            当时钟高电平时, 不执行 (latch_en 保持原值, 隐式锁存)
    // 这确保了:
    //   1) enable的更新只在 clk 低电平期间发生
    //   2) clk 高电平期间 latch_en 稳定不变
    //   3) gated_clk 不会出现毛刺
    // =======================================================================
    always @(clk or enable) begin
        if (!clk) begin            // 时钟低电平: 锁存器透明
            latch_en <= enable;    // 采样 enable 信号
        end
        // 时钟高电平: latch_en 保持 (隐式锁存, 不执行任何操作)
    end

    // =======================================================================
    // 时钟门控逻辑: AND 门
    // gated_clk = clk AND latch_en
    // clk=1 且 latch_en=1 -> gated_clk = 1 (时钟脉冲通过)
    // clk=0 或 latch_en=0 -> gated_clk = 0 (时钟停止)
    // =======================================================================
    assign gated_clk = clk & latch_en;

endmodule
