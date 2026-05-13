// =============================================================================
// 模块名称: sync_fifo_mem (同步FIFO存储器阵列)
// 功能描述: FIFO的存储体, 以MEM_WIDTH为单位存储数据。
//           自动处理读写宽度转换:
//           - 读宽度>写宽度: 多个写入单元拼接为一个读取
//           - 写宽度>读宽度: 一个写入拆分为多个读取单元
// 两种工作模式 (由generate选择):
//   Mode A (R_DATA_WIDTH > W_DATA_WIDTH):
//     写入: 每次写1个MEM_WIDTH单元 (wr_data直接写入1个mem位置)
//     读取: 每次读R_DATA_WIDTH/MEM_WIDTH个连续单元拼接输出
//   Mode B (R_DATA_WIDTH <= W_DATA_WIDTH):
//     写入: 每次写W_DATA_WIDTH/MEM_WIDTH个连续单元
//     读取: 每次读1个MEM_WIDTH单元
// =============================================================================

module sync_fifo_mem #(
    // 读数据宽度
    parameter R_DATA_WIDTH = 64,
    // 写数据宽度
    parameter W_DATA_WIDTH = 16,
    // 存储器单元宽度 = min(R, W)
    parameter MEM_WIDTH    = 16,
    // FIFO深度(以MEM_WIDTH为单位)
    parameter FIFO_DEPTH   = 256,
    // 地址位宽
    parameter ADDR_WIDTH   = 4
)(
    input  wire                      clk,
    input  wire                      wr_en,           // 写使能
    input  wire                      rd_en,           // 读使能
    input  wire [ADDR_WIDTH - 1:0]   wr_addr,         // 写地址
    input  wire [ADDR_WIDTH - 1:0]   rd_addr,         // 读地址

    input  wire [W_DATA_WIDTH - 1:0] wr_data,         // 写数据
    output wire [R_DATA_WIDTH - 1:0] rd_data          // 读数据
);

    // 存储器: MEM_WIDTH位宽 × FIFO_DEPTH深度
    reg [MEM_WIDTH - 1:0] mem [0:FIFO_DEPTH - 1];

    generate
        // ---- Mode A: R > W (读打包模式) ----
        // 写: 每次存1个单元
        // 读: 每次读R/MEM个连续单元, 拼接为R_DATA_WIDTH输出
        if (R_DATA_WIDTH > W_DATA_WIDTH) begin
            // 写逻辑: negedge clk, wr_en时写入
            always @(negedge clk) begin
                if (wr_en) begin
                    mem[wr_addr] <= wr_data;
                end
            end

            // 读逻辑: 生成genvar循环, 用assign拼接
            genvar k;
            for (k = 0; k < R_DATA_WIDTH/MEM_WIDTH; k = k + 1) begin : read_mem
                // rd_data的每个MEM_WIDTH切片 = 从rd_addr+k读出的数据
                // 用part-select: [(k+1)*MEM_WIDTH-1 -: MEM_WIDTH]
                assign rd_data[(k+1)*MEM_WIDTH-1 -: MEM_WIDTH] = (rd_en)? mem[rd_addr + k] : 'b0;
            end
        end else begin
            // ---- Mode B: W >= R (写拆分模式) ----
            integer i;

            // 写逻辑: 将宽数据拆分为多个MEM_WIDTH单元, 存入连续地址
            always @(negedge clk) begin
                if (wr_en) begin
                    for (i = 0; i < W_DATA_WIDTH/MEM_WIDTH; i = i + 1) begin
                    mem[wr_addr + i] <= wr_data[(i+1)*MEM_WIDTH-1 -: MEM_WIDTH];
                    end
                end
            end

            // 读逻辑: 每次读1个单元 (R = MEM_WIDTH)
            assign rd_data = (rd_en)? mem[rd_addr] : 'b0;
        end
    endgenerate

endmodule
