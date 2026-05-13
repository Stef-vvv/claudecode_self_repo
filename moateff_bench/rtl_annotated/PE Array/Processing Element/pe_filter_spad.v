// ============================================================================
// 模块名称: filter_spad (滤波器权重便签存储器 - Filter Scratchpad)
// 架构位置: pe.v 内部的滤波器权重存储子模块
//           pe(PE核心) -> filter_spad(本模块)
//
// 模块功能: 存储滤波器权重数据的便签存储器 (SPAD = Scratchpad)
//           - 外部写入: w_en=1 时在 w_addr 位置写入 din
//           - 内部读取: r_en=1 时从 r_addr 读出到 dout
//           - 写地址自增: 每次写入后 w_addr 自动 +1
//           - 深度控制: full = (w_addr == spad_depth)
//           - 空标志:   empty = (w_addr == r_addr) 即写指针追上读指针
//
// 存储组织:
//   深度: FILTER_SPAD_DEPTH = 224 (最大)
//   实际使用深度: spad_depth = p * q * S (如 5*3*4 = 60)
//   宽度: DATA_WIDTH = 16-bit (Q0.8 定点)
//   实现: Block RAM (ram_style = "block")
//
// 与 ifmap_spad 的区别:
//   - 无移位功能 (filter权重固定, 不需要滑动窗口)
//   - 无复位对 w_addr 的影响 (复用期间无需清空)
// ============================================================================
module filter_spad
#(
    parameter MEM_DEPTH  = 224,              // 最大存储深度 (条目数)
    parameter DATA_WIDTH = 16,               // 数据宽度 (bit)
    parameter ADDR_WIDTH = $clog2(MEM_DEPTH) // 地址位宽 = $clog2(224) = 8
)(
    input  wire                    clk,        // 时钟 (negedge触发)
    input  wire                    reset,      // 异步复位 (高有效, 清零w_addr)

    input  wire [ADDR_WIDTH - 1:0] spad_depth,// 实际使用的深度 (p*q*S, 截断到地址位宽)

    input  wire                    w_en,       // 写使能: 1=写入一个权重
    input  wire [DATA_WIDTH - 1:0] din,        // 写入数据 (filter权重, 16-bit Q0.8)

    input  wire                    r_en,       // 读使能: 1=读出一个权重
    input  wire [ADDR_WIDTH - 1:0] r_addr,     // 读地址 (来自控制器: i*p + j)
    output reg  [DATA_WIDTH - 1:0] dout,       // 读出数据 -> 乘法器输入

    output wire                    full,       // 满标志: w_addr == spad_depth
    output wire                    empty       // 空标志: w_addr == r_addr
);

    // =======================================================================
    // Block RAM 存储体
    // (* ram_style = "block" *): 综合为 Block RAM (而非分布式RAM/LUTRAM)
    // 深度: MEM_DEPTH, 宽度: DATA_WIDTH
    // 地址范围: 0 到 MEM_DEPTH-1
    // =======================================================================
    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

    // 写地址指针: 指向下一次写入位置, 初始为0, 每次写入后自增
    reg [$clog2(MEM_DEPTH)-1:0] w_addr;

    // =======================================================================
    // SPAD 读写逻辑 (negedge clk, 无复位)
    // 同时支持读写操作 (简单双端口行为)
    // 写: w_en=1 时 mem[w_addr] <= din (写当前 w_addr 位置)
    // 读: r_en=1 时 dout <= mem[r_addr] (读指定地址)
    // 注意: 读写同时发生时, 读操作读到的是写入前的旧值
    //       (Read-First 行为, 不是 Write-First)
    // =======================================================================
    always @(negedge clk) begin
        if (w_en) begin
            mem[w_addr] <= din;      // 写入: 在当前写指针位置存储权重
        end
        if (r_en) begin
            dout <= mem[r_addr];     // 读取: 从控制器指定地址读出权重
        end
    end

    // =======================================================================
    // 写地址管理 (negedge clk 或 posedge reset)
    // reset: w_addr = 0 (复位到起始位置)
    // w_en:  w_addr = w_addr + 1 (每次写入后地址自增)
    // 注意: w_addr 不受读操作影响, 只在写入时递增
    // =======================================================================
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            w_addr <= 'b0;           // 复位: 写指针归零
        end else if (w_en) begin
            w_addr <= w_addr + 1;    // 写入后地址 +1 (指向下一个空位置)
        end
    end

    // =======================================================================
    // 满/空标志 (组合逻辑)
    // full:  写地址达到 spad_depth -> SPAD 已满, 不能再写入
    // empty: 写地址 == 读地址 -> 所有写入数据已被读完
    //        假设正常操作中, 写总是在读之前 (先填充后计算)
    //        且 w_addr >= r_addr (写不落后于读)
    // =======================================================================
    assign full  = (w_addr == spad_depth) ? 1'b1 : 1'b0;
    assign empty = (w_addr == r_addr)   ? 1'b1 : 1'b0;

endmodule
