// ============================================================================
// 模块名称: ifmap_spad (输入特征图便签存储器 - Ifmap Scratchpad)
// 架构位置: pe.v 内部的 ifmap 数据存储子模块
//           pe(PE核心) -> ifmap_spad(本模块)
//
// 模块功能: 存储 ifmap (输入特征图) 滑动窗口数据
//           - 外部写入: w_en=1 时在 w_addr 位置写入 din
//           - 内部读取: r_en=1 时从 r_addr 读出到 dout
//           - 移位操作: shift=1 时所有数据左移一位 [i] <= [i+1]
//             (用于实现 ifmap 滑动窗口, 丢弃最左列, 加载新列)
//           - 写地址管理: 写入时+1, 移位时-1
//           - 深度控制: full = (w_addr == spad_depth)
//           - 空标志:   empty = (w_addr == r_addr)
//
// 存储组织:
//   深度: IFMAP_SPAD_DEPTH = 12 (最大)
//   实际使用深度: spad_depth = q * S (如 3*4 = 12: 3列x4行)
//   宽度: DATA_WIDTH = 16-bit (Q0.8 定点)
//   实现: shift_reg 寄存器阵列 (非Block RAM, 因为需要移位)
//
// 滑动窗口机制:
//   每次 STRIDE 状态时 shift=1, 窗口左移:
//   shift_reg[0] <= shift_reg[1]
//   shift_reg[1] <= shift_reg[2]
//   ...
//   shift_reg[10] <= shift_reg[11]
//   最后一列 shift_reg[11] 被丢弃 (或由外部重新加载)
//
// 与 filter_spad 的区别:
//   - 有移位功能 (实现滑动窗口)
//   - 使用寄存器阵列 (shift_reg) 而非 Block RAM
//   - 移位时 w_addr 减1 (因为数据左移后写指针位置前移)
// ============================================================================
module ifmap_spad
#(
    parameter MEM_DEPTH  = 12,               // 最大存储深度
    parameter DATA_WIDTH = 16,               // 数据宽度
    parameter ADDR_WIDTH = $clog2(MEM_DEPTH) // 地址位宽 = $clog2(12) = 4
)(
    input  wire                    clk,        // 时钟 (negedge)
    input  wire                    reset,      // 异步复位 (高有效, 清零w_addr)

    input  wire [ADDR_WIDTH - 1:0] spad_depth, // 实际使用的 SPAD 深度 (q * S)

    input  wire                    shift,      // 移位使能: 1=窗口左移一列
    input  wire                    w_en,       // 写使能: 1=写入一个像素
    input  wire [DATA_WIDTH - 1:0] din,        // 写入数据 (ifmap像素, 16-bit Q0.8)

    input  wire [ADDR_WIDTH - 1:0] r_addr,     // 读地址 (来自控制器: i_crnt)
    input  wire                    r_en,       // 读使能: 1=读出一个像素
    output reg  [DATA_WIDTH - 1:0] dout,       // 读出数据 -> 乘法器输入

    output wire full,                          // 满标志: w_addr == spad_depth
    output wire empty                          // 空标志: w_addr == r_addr
);

    // =======================================================================
    // 移位寄存器阵列 (shift register array)
    // 使用寄存器而非Block RAM, 因为需要支持移位操作
    // 深度: MEM_DEPTH (如12), 宽度: DATA_WIDTH (16-bit)
    // =======================================================================
    reg [DATA_WIDTH-1:0] shift_reg [0:MEM_DEPTH-1];

    // 写地址指针: 指向下一个写入位置
    // 写入时自增(+1), 移位时自减(-1)
    reg [$clog2(MEM_DEPTH)-1:0] w_addr;

    integer i;
    // =======================================================================
    // 移位/写入/读取逻辑 (negedge clk, 无复位)
    // 优先级: shift > w_en (移位优先于写入)
    // 读操作与移位/写入并行 (可以同时进行)
    //
    // 移位操作: 所有元素左移一位
    //   for i=0..MEM_DEPTH-2: shift_reg[i] <= shift_reg[i+1]
    //   最后一个位置 shift_reg[MEM_DEPTH-1] 保持不变 (旧数据)
    //
    // 写入操作: shift_reg[w_addr] <= din
    //   仅当 shift=0 时才执行写入
    //
    // 读取操作: dout <= shift_reg[r_addr]
    //   始终可读 (独立于移位/写入)
    // =======================================================================
    always @(negedge clk) begin
        if (shift) begin
            // 移位: 所有元素左移, 实现滑动窗口
            for (i = 0; i < MEM_DEPTH - 1; i = i + 1) begin
                shift_reg[i] <= shift_reg[i + 1];
            end
            // shift_reg[MEM_DEPTH-1] 保持旧值 (将被后续写入覆盖)
        end else if (w_en) begin
            // 写入新像素到当前写指针位置
            shift_reg[w_addr] <= din;
        end
        if (r_en) begin
            // 读取指定地址的像素
            dout <= shift_reg[r_addr];
        end
    end


    // =======================================================================
    // 写地址管理 (negedge clk 或 posedge reset)
    // reset: w_addr = 0 (复位)
    // shift: w_addr = w_addr - 1 (移位后, 新的写入位置前移)
    // w_en:  w_addr = w_addr + 1 (写入后指针后移)
    // 注意: shift 和 w_en 互斥 (由 always 块的 if-else if 保证)
    //       因为 ifmap_spad_full 在 shift 时也置1, 阻止外部写入
    // =======================================================================
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            w_addr <= 'b0;            // 复位: 写指针归零
        end else if (shift) begin
            w_addr <= w_addr - 1;     // 移位: 数据左移, 可写入位置前移一位
        end else if (w_en) begin
            w_addr <= w_addr + 1;     // 写入: 指针后移, 指向下一个空位
        end
    end

    // =======================================================================
    // 满/空标志 (组合逻辑)
    // full:  w_addr == spad_depth -> SPAD已满, 不能再接收
    // empty: w_addr == r_addr -> 写入的数据都已被读取
    // =======================================================================
    assign full  = (w_addr == spad_depth) ? 1'b1 : 1'b0;
    assign empty = (w_addr == r_addr)   ? 1'b1 : 1'b0;

endmodule

