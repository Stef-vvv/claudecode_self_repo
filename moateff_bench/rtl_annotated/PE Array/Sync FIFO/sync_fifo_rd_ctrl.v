// =============================================================================
// 模块名称: sync_fifo_rd_ctrl (同步FIFO读控制器)
// 功能描述: 管理FIFO的读指针(rd_ptr), 产生读使能(rd_en)和空标志(empty_flag)。
// 空检测规则:
//   等宽(LIMIT=0): empty_flag = (wr_ptr == rd_ptr)
//   不等宽(LIMIT>0): empty_flag = (wr_ptr[ADDR_WIDTH:LIMIT] == rd_ptr[ADDR_WIDTH:LIMIT])
//     仅比较高地址位, 忽略低LIMIT位(因为写/读步长不同)
// 读指针递增步长:
//   R == MEM: rd_ptr += 1
//   R > MEM:  rd_ptr += R/MEM (一次读多个单元)
// =============================================================================

module sync_fifo_rd_ctrl #(
    // 读数据宽度
    parameter R_DATA_WIDTH = 16,
    // 写数据宽度
    parameter W_DATA_WIDTH = 16,
    // 存储器单元宽度
    parameter MEM_WIDTH    = 16,
    // 宽度比对数: 0=等宽
    parameter LIMIT        = 0,
    // FIFO深度
    parameter FIFO_DEPTH   = 256,
    // 地址位宽
    parameter ADDR_WIDTH   = 4
)(
    input wire                    clk,
    input wire                    reset,
    input wire                    rd_request,      // 外部读请求
    input wire [ADDR_WIDTH:LIMIT] wr_ptr,           // 写指针(高位, 用于空检测)

    output reg [ADDR_WIDTH:0] rd_ptr,               // 读指针 (多1位用于环绕检测)
    output wire                rd_en,                // 内部读使能
    output wire               empty_flag             // 空标志
);

    // 空检测: 比较读指针和写指针的高位
    // 等宽时直接比较, 不等宽时忽略低LIMIT位
    assign empty_flag = (wr_ptr[ADDR_WIDTH : LIMIT] == rd_ptr[ADDR_WIDTH : LIMIT]);

    // 读使能: 非空时可读 (由下游read_ctrl保证读出数据有效)
    assign rd_en = ~empty_flag;

    // 读指针递增条件: 外部请求 & 非空
    wire rd_ptr_inc;
    assign rd_ptr_inc = rd_request & (~empty_flag);

    generate
        // R == MEM: 读宽度 = 存储单元宽度
        if (R_DATA_WIDTH == MEM_WIDTH) begin
            always @(negedge clk or posedge reset) begin
                if (reset) begin
                    rd_ptr <= 0;
                end else if (rd_ptr_inc) begin
                    rd_ptr <= rd_ptr + 1;    // 步长=1
                end
            end
        end else begin
            // R > MEM: 读宽度是存储单元的倍数
            always @(negedge clk or posedge reset) begin
                if (reset) begin
                    rd_ptr <= 0;
                end else if (rd_ptr_inc) begin
                    rd_ptr <= rd_ptr + (R_DATA_WIDTH / MEM_WIDTH);  // 步长=倍数
                end
            end
        end
    endgenerate

endmodule
