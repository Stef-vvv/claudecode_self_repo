// =============================================================================
// 模块名称: sync_fifo_wr_ctrl (同步FIFO写控制器)
// 功能描述: 管理FIFO的写指针(wr_ptr), 产生写使能(wr_en)和满标志(full_flag)。
// 满检测规则:
//   等宽(LIMIT=0): full_flag = (rd_ptr[ADDR_WIDTH-1:0] == wr_ptr[ADDR_WIDTH-1:0])
//                              && (rd_ptr[ADDR_WIDTH] != wr_ptr[ADDR_WIDTH])
//     地址相同但高位不同 -> FIFO已环绕 -> 满
//   不等宽(LIMIT>0): 类似, 但忽略低LIMIT位
// 写指针递增步长:
//   W == MEM: wr_ptr += 1
//   W > MEM:  wr_ptr += W/MEM (一次写多个单元)
// =============================================================================

module sync_fifo_wr_ctrl #(
    // 读数据宽度
    parameter R_DATA_WIDTH = 8,
    // 写数据宽度
    parameter W_DATA_WIDTH = 16,
    // 存储器单元宽度
    parameter MEM_WIDTH    = 16,
    // 宽度比对数
    parameter LIMIT        = 0,
    // FIFO深度
    parameter FIFO_DEPTH   = 64,
    // 地址位宽
    parameter ADDR_WIDTH   = 4
)(
    input wire                    clk,
    input wire                    reset,
    input wire                    wr_request,      // 外部写请求
    input wire [ADDR_WIDTH:LIMIT] rd_ptr,           // 读指针(用于满检测)

    output reg [ADDR_WIDTH:0] wr_ptr,               // 写指针 (多1位用于环绕检测)
    output wire               wr_en,                // 内部写使能
    output wire               full_flag             // 满标志
);

    // 满检测:
    // 地址低位相等 AND 最高位不同 -> 写指针已环绕超过读指针 -> FIFO满
    assign full_flag = (rd_ptr[ADDR_WIDTH - 1 : LIMIT] == wr_ptr[ADDR_WIDTH - 1 : LIMIT]) &&
                       (rd_ptr[ADDR_WIDTH] != wr_ptr[ADDR_WIDTH]);

    // 写使能: 外部请求 & 非满
    assign wr_en = wr_request  & (~full_flag);

    // 写指针递增条件
    wire wr_ptr_inc;
    assign wr_ptr_inc = wr_en;

    generate
        // W == MEM: 写宽度 = 存储单元宽度
        if (W_DATA_WIDTH == MEM_WIDTH) begin
            always @(negedge clk or posedge reset) begin
                if (reset) begin
                    wr_ptr <= 0;
                end else if (wr_ptr_inc) begin
                    wr_ptr <= wr_ptr + 1;    // 步长=1
                end
            end
        end else  begin
            // W > MEM: 写宽度是存储单元的倍数
            always @(negedge clk or posedge reset) begin
                if (reset) begin
                    wr_ptr <= 0;
                end else if (wr_ptr_inc) begin
                    wr_ptr <= wr_ptr + (W_DATA_WIDTH / MEM_WIDTH);  // 步长=倍数
                end
            end
        end
    endgenerate

endmodule
