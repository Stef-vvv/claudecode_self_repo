// ============================================================================
// 模块名称: scan_ff_Nbit (N位扫描链寄存器)
// 在架构中的位置: SCAN CHAIN - 参数化位宽的扫描配置寄存器
//
// 功能描述:
//   将DATA_WIDTH个scan_ff单元串联成一条扫描链，实现多比特参数的配置。
//   移位方向: scan_in(MSB侧) -> 最高位 -> ... -> 最低位 -> scan_out
//
//   扫描链结构:
//   scan_in -> [scan_ff DATA_WIDTH-1] -> ... -> [scan_ff 0] -> scan_out
//   scan_w[i+1] 是第i个scan_ff的scan_in
//   scan_w[i]   是第i个scan_ff的scan_out
//
//   使用generate-for展开（使用genvar保证编译器展开为硬件实例而非循环）
//
// 时钟域说明:
//   - negedge clk + posedge reset，所有scan_ff同步
// ============================================================================

module scan_ff_Nbit #(parameter DATA_WIDTH = 4) (  // 参数位宽（默认4位）
    input  wire clk,                               // 时钟（negedge触发）
    input  wire reset,                             // 异步复位
    input  wire scan_en,                           // 扫描使能（1=移位，0=正常输出）
    input  wire scan_in,                           // 扫描链串行输入
    output wire [DATA_WIDTH - 1:0] q,              // 并行配置输出（N位宽）
    output wire scan_out                           // 扫描链串行输出（最低位输出）
);

    // ========================================================================
    // scan_w: 扫描链内部连线
    // scan_w[DATA_WIDTH] = scan_in (最高位入口)
    // scan_w[i] 连接 scan_ff_i 的 scan_out
    // scan_w[0] = scan_out (最低位出口)
    // ========================================================================
    wire [DATA_WIDTH:0] scan_w;

    assign scan_w[DATA_WIDTH] = scan_in;   // 入口: 最高位连接扫描输入
    assign scan_out = scan_w[0];           // 出口: 最低位连接扫描输出

    // ========================================================================
    // 使用generate-for将DATA_WIDTH个scan_ff串联成扫描链
    // 从高位(i=DATA_WIDTH-1)向低位(i=0)串联
    // ========================================================================
    genvar i;
    generate
        for (i = DATA_WIDTH - 1; i >= 0; i = i - 1) begin : SCAN_FF
            scan_ff scan_ff_inst (
                .clk(clk),
                .reset(reset),
                .scan_en(scan_en),
                .scan_in(scan_w[i+1]),      // 输入来自上一级（更高位）的scan_out
                .q(q[i]),                   // 输出到并行配置总线
                .scan_out(scan_w[i])         // 输出到下一级（更低位）的scan_in
            );
        end
    endgenerate

endmodule
