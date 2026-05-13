// ============================================================================
// 模块名称: zero_skipping (零值跳过缓冲区)
// 架构位置: pe.v 内部的零值检测与跳过子模块
//           pe(PE核心) -> zero_skipping(本模块)
//
// 模块功能: 存储每个ifmap像素是否为零的标志位 (1-bit per pixel)
//           - 外部写入: w_en=1 时记录 din==0 的标志
//           - 内部读取: r_addr 位置读出 zero_flag
//           - 移位操作: shift=1 时所有标志左移 (与ifmap_spad同步)
//           - zero_flag 用于门控乘法器和SPAD读使能:
//             ifmap为零时关闭乘法器, 节省动态功耗
//
// 零跳过原理:
//   卷积中的零值像素 (ReLU输出、边界padding) 对结果无贡献
//   跳过它们的乘法和累加可以节省大量功耗
//   zero_flag=1 时:
//     - SPAD读使能门控: r_en = (~zero_flag) & rd_data (不读)
//     - 乘法器使能门控: en_mul = (~zero_flag) & rd_data (不乘)
//
// 存储组织:
//   深度: 与 IFMAP_SPAD_DEPTH 一致 (如12)
//   宽度: 1-bit (零标志: 1=当前像素为零)
//   结构: zero_buffer 寄存器阵列 (需移位, 不用Block RAM)
//
// 与 ifmap_spad 的同步:
//   - 相同深度, 相同地址管理
//   - 同时移位 (shift使能共享)
//   - 地址完全对应: zero_buffer[i] 对应 ifmap_spad.shift_reg[i] 的零标志
// ============================================================================
module zero_skipping
#(
    parameter MEM_DEPTH  = 12,               // 最大存储深度 (与ifmap SPAD一致)
    parameter DATA_WIDTH = 16,               // 输入数据宽度 (用于零值比较)
    parameter ADDR_WIDTH = $clog2(MEM_DEPTH) // 地址位宽 = $clog2(12) = 4
)(
    input  wire                    clk,        // 时钟 (negedge)
    input  wire                    reset,      // 异步复位 (高有效)

    input  wire                    shift,      // 移位使能: 与ifmap_spad同步
    input  wire                    w_en,       // 写使能: 写入ifmap时记录零标志
    input  wire [DATA_WIDTH - 1:0] din,        // 写入数据: 用于零值比较

    input  wire [ADDR_WIDTH - 1:0] r_addr,     // 读地址: 与ifmap_spad同步
    output wire                    zero_flag   // 零标志输出: 1=对应像素为零
);

    // =======================================================================
    // 零标志缓冲区 (1-bit 寄存器阵列)
    // 存储每个ifmap位置的零标志
    // 使用1-bit寄存器, 深度与ifmap_spad相同
    // =======================================================================
    reg [0:0] zero_buffer [0:MEM_DEPTH - 1];

    // 写地址指针 (与ifmap_spad的w_addr管理方式相同)
    reg [$clog2(MEM_DEPTH)-1:0] w_addr;

    integer i;
    // =======================================================================
    // 移位/写入逻辑 (negedge clk, 无复位)
    // 与 ifmap_spad 的行为完全一致:
    //   shift=1: 所有标志左移 (zero_buffer[i] <= zero_buffer[i+1])
    //   w_en=1:  在 w_addr 位置记录 din==0 的标志
    // 注: 读取为组合逻辑 (assign zero_flag = zero_buffer[r_addr])
    // =======================================================================
    always @(negedge clk) begin
        if (shift) begin
            // 移位: 所有零标志左移, 与ifmap窗口同步
            for (i = 0; i < MEM_DEPTH - 1; i = i + 1) begin
                zero_buffer[i] <= zero_buffer[i + 1];
            end
        end else if (w_en) begin
            // 写入: 记录当前像素是否为零
            // din == 0 -> zero_buffer[w_addr] = 1 (零标志)
            // din != 0 -> zero_buffer[w_addr] = 0 (非零)
            zero_buffer[w_addr] <= (din == {DATA_WIDTH{1'b0}});
        end
    end

    // =======================================================================
    // 零标志读出 (组合逻辑)
    // 从 zero_buffer 的 r_addr 位置读出零标志
    // 直接组合输出, 无需时钟 (与ifmap_spad的读时序对齐)
    // =======================================================================
    assign zero_flag = zero_buffer[r_addr];

    // =======================================================================
    // 写地址管理 (negedge clk 或 posedge reset)
    // 与 ifmap_spad 地址管理完全一致:
    //   reset: w_addr = 0
    //   shift: w_addr = w_addr - 1 (左移后写指针前移)
    //   w_en:  w_addr = w_addr + 1 (写入后指针后移)
    // =======================================================================
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            w_addr <= 'b0;            // 复位: 写指针归零
        end else if (shift) begin
            w_addr <= w_addr - 1;     // 移位: 与ifmap_spad同步前移
        end else if (w_en) begin
            w_addr <= w_addr + 1;     // 写入: 指针后移
        end
    end

endmodule
