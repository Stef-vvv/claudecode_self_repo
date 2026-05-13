// ============================================================================
// 模块名称: flopr (带复位流水线寄存器 / Pipeline Register with Reset)
// 架构位置: pe.v 内部用于流水线对齐的通用寄存器
//           pe(PE核心) -> flopr(本模块) 多处实例化
//
// 模块功能: 参数化宽度的 D 触发器 (带异步复位)
//           - reset=1: q = 0 (异步复位, 清零)
//           - reset=0: q <= d (在 negedge clk 采样输入)
//
// 使用场景 (在 pe.v 中共3个实例):
//   reg1: 一级流水 (PSUM_ADDR_WIDTH + 3 bits)
//         打包 psum_addr, wr_psum, accumulate_ipsum, pad
//   reg2: 二级流水 (PSUM_ADDR_WIDTH + 3 bits)
//         打包上述信号的 _r 版本, 生成 _rr 版本
//   reg3: 一级流水 (DATA_WIDTH + 2 bits)
//         打包 mux1_out, en_mul, reset_accumulation
//
// 流水线目的:
//   控制信号和地址需要经过流水延迟, 以对齐 MAC 数据通路:
//   MAC 路径: SPAD读 -> 乘法器(1级) -> 截断器(组合) -> 加法器(组合)
//   控制路径: 控制器 -> reg1(1级) -> reg2(2级) -> SPAD写/加法器控制
//   通过 reg1/reg2 使控制信号与数据到达时间对齐
// ============================================================================
module flopr
#(
    parameter DATA_WIDTH = 16            // 寄存器宽度 (可参数化, 默认16)
)(
    input wire clk, reset,               // 时钟 (negedge), 异步复位 (posedge)
    input wire [DATA_WIDTH-1:0] d,       // 数据输入
    output reg [DATA_WIDTH-1:0] q        // 数据输出 (寄存后)
);

    // =======================================================================
    // 寄存器时序逻辑
    // always @(negedge clk or posedge reset): 下降沿触发, 异步复位
    // reset=1:  q <= 0 (所有位清零)
    // reset=0:  q <= d (正常采样)
    // =======================================================================
    always @(negedge clk or posedge reset) begin
        if (reset)
            q <= {DATA_WIDTH{1'b0}};     // 异步清零 (扩展到DATA_WIDTH位)
        else
            q <= d;                      // 在下降沿锁存输入
    end

endmodule

