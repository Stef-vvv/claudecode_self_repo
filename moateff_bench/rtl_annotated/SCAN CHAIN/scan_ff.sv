// ============================================================================
// 模块名称: scan_ff (扫描链触发器 / 单比特扫描单元)
// 在架构中的位置: SCAN CHAIN - 配置扫描链的基本单元
//
// 功能描述:
//   单个扫描触发器单元，支持两种模式:
//   1. 正常模式(scan_en=0): q输出锁存的内部值（配置数据生效）
//   2. 扫描模式(scan_en=1): 扫描链移位，scan_in -> q_internal -> scan_out
//
//   架构说明:
//   - q_internal: 内部锁存的状态值
//   - scan_en=0: q = q_internal (正常输出配置值), 且不接收新输入
//   - scan_en=1: q_internal <= scan_in (移位), q = 0 (扫描时输出禁用)
//   - scan_out 始终等于 q_internal
//
//   注意: d端口被注释掉，本设计不使用并行加载(parallel load)方式配置，
//         仅通过scan_en控制的串行移位来配置参数。
//
// 时钟域说明:
//   - negedge clk触发 + posedge reset异步复位
//   - 与core_clk同步
// ============================================================================

module scan_ff (
    input  wire clk,          // 时钟（negedge触发）
    input  wire reset,        // 异步复位（高有效）
    input  wire scan_en,      // 扫描使能（1=移位模式，0=正常模式/保持）
    input  wire scan_in,      // 扫描链输入（来自上一级的scan_out）
    // input  wire d,          // 并行数据输入（已注释，仅使用串行扫描）
    output wire q,            // 配置位输出（正常模式下有效）
    output wire scan_out      // 扫描链输出（连到下一级的scan_in）
);

    // ========================================================================
    // q_internal: 内部状态寄存器
    // 复位时清零
    // scan_en=1: 移位，将scan_in锁存到内部
    // scan_en=0: 保持当前值
    // ========================================================================
    reg q_internal;

    always @(negedge clk or posedge reset) begin
        if (reset)
            q_internal <= 1'b0;          // 复位清零
        else if (scan_en)
            q_internal <= /*(~scan_en) ? d :*/scan_in;  // 扫描模式: 移入新位
                                                         // 注释的代码表明d端口被省略
    end

    // ========================================================================
    // 输出逻辑:
    // - scan_en=0 (正常模式): q = q_internal (配置值输出)
    // - scan_en=1 (扫描模式): q = 0 (输出禁用，避免错误配置值影响电路)
    // - scan_out: 始终输出q_internal给下一级
    // ========================================================================
    assign q = (~scan_en) & q_internal;  // 仅正常模式输出配置值
    assign scan_out = q_internal;        // 扫描链持续输出

endmodule
