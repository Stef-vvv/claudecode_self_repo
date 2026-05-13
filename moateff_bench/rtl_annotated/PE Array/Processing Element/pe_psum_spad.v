// ============================================================================
// 模块名称: psum_spad (部分和便签存储器 - Psum Scratchpad)
// 架构位置: pe.v 内部的 psum 数据存储子模块
//           pe(PE核心) -> psum_spad(本模块)
//
// 模块功能: 存储部分和 (每个输出通道一个累加器)
//           - 写入: w_en=1 时在 w_addr 位置写入 din (posedge clk)
//           - 读取: dout = mem[r_addr] (negedge clk)
//           - 半周期转发: 写用posedge, 读用negedge
//             同周期内, 写操作在posedge完成, 读操作在negedge读出
//             如果写和读是同一地址, 读可得到写入的新值 (半周期旁路)
//
// 存储组织:
//   深度: PSUM_SPAD_DEPTH = 24 (最大)
//   实际使用深度: p (输出通道分片数, 如5)
//   宽度: DATA_WIDTH = 16-bit (Q0.8 定点)
//   实现: 寄存器阵列 (非法Block RAM, 因为需要半周期读写)
//
// 写地址管理:
//   写地址由外部控制器提供 (psum_addr_rr, 经过两级流水延迟)
//   读地址由外部控制器提供 (psum_addr, 直接来自控制器)
//   地址在 pe.v 中通过流水线寄存器对齐MAC时序
//
// 半周期读写机制:
//   1. posedge clk: 写入 mem[w_addr] <= din (加法器的 sum_result)
//   2. negedge clk: dout <= mem[r_addr] (下一个周期的SPAD读出)
//   由于negedge在posedge之后, 如果 w_addr == r_addr:
//     读到的可能是刚写入的新值 (取决于仿真/综合行为)
//     为避免不确定性, pe.v 中使用 forward MUX 进行数据转发
// ============================================================================
module psum_spad
#(
    parameter MEM_DEPTH  = 24,               // 最大存储深度 (条目数)
    parameter DATA_WIDTH = 16,               // 数据宽度 (bit)
    parameter ADDR_WIDTH = $clog2(MEM_DEPTH) // 地址位宽 = $clog2(24) = 5
)(
    input  wire                    clk,       // 时钟 (读写使用不同沿)

    input  wire                    w_en,      // 写使能: 1=写入部分和
    input  wire [DATA_WIDTH - 1:0] din,       // 写入数据 (加法器输出 = 新部分和)
    input  wire [ADDR_WIDTH - 1:0] w_addr,    // 写地址 (psum_addr_rr, 两级流水延迟)

    input  wire [ADDR_WIDTH - 1:0] r_addr,    // 读地址 (psum_addr, 控制器直接输出)
    output reg  [DATA_WIDTH - 1:0] dout       // 读出数据 -> 转发MUX
);

    // =======================================================================
    // 寄存器阵列存储体
    // 深度: MEM_DEPTH (24), 宽度: DATA_WIDTH (16)
    // 不使用 Block RAM, 因为需要半周期读写 (posedge写 + negedge读)
    // =======================================================================
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // =======================================================================
    // 写逻辑 (posedge clk)
    // w_en=1 时将 din 写入 mem[w_addr]
    // posedge 写入确保数据在下降沿读取之前已经稳定
    // =======================================================================
    always @(posedge clk) begin
        if (w_en) begin
            mem[w_addr] <= din;      // 在上升沿写入新部分和
        end
    end

    // =======================================================================
    // 读逻辑 (negedge clk)
    // 在下降沿读出 mem[r_addr]
    // 由于下降沿在上升沿之后, 同地址写读存在竞争
    // 所以在 pe.v 中使用 forward MUX 处理这种情况:
    //   forward = wr_psum_rr & (psum_addr_r == psum_addr_rr)
    //   转发时绕过 SPAD 直接使用 sum_result
    // =======================================================================
    always @(negedge clk) begin
        dout <= mem[r_addr];         // 在下降沿读出
    end

endmodule
