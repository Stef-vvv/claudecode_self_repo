// =============================================================================
// 模块名称: gin_wrapper (GIN 包装器)
// 功能描述: 在GIN(全局输入网络)基础上增加两个同步FIFO进行流量控制。
//           一个FIFO缓存标签(row_tag + col_tag), 另一个FIFO缓存数据。
//           标签和数据同步读出, 保证每个数据都有正确的路由标签。
// 数据流角色: GIN的缓冲入口 —— 上游NoC Controller写入标签+数据,
//           内部FIFO同步读出后送入GIN核心进行广播分发。
// =============================================================================

module gin_wrapper
#(
    // 数据位宽
    parameter DATA_WIDTH    = 64,
    // 行标签位宽
    parameter ROW_TAG_WIDTH = 4,
    // 列标签位宽
    parameter COL_TAG_WIDTH = 4,
    // PE阵列行数
    parameter NUM_OF_ROWS   = 12,
    // PE阵列列数
    parameter NUM_OF_COLS   = 14,
    // 数据FIFO深度
    parameter GIN_DATA_FIFO_DEPTH = 4096,
    // 标签FIFO深度
    parameter GIN_TAGS_FIFO_DEPTH = 4096
)(
    input clk,
    input reset,

    // 行标签输入: 指示目标行
    input [ROW_TAG_WIDTH - 1:0] row_tag,
    // 列标签输入: 指示目标列
    input [COL_TAG_WIDTH - 1:0] col_tag,

    // PE阵列各单元的ready信号: ready_in[row][col]
    input  [0:NUM_OF_COLS - 1] ready_in [0:NUM_OF_ROWS - 1],
    // 数据输入(来自NoC Controller)
    input  [DATA_WIDTH - 1:0]  data_in,   
    // 数据输出到PE阵列: 2D数组
    output [DATA_WIDTH - 1:0]  data_out   [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS - 1],
    // 输出使能到PE阵列
    output [0:NUM_OF_COLS - 1] enable_out [0:NUM_OF_ROWS - 1],
    
    // 标签FIFO写使能(来自NoC Controller)
    input tags_wr_en,
    // 标签FIFO满标志(反馈给NoC Controller, 用于流控)
    output tags_full,
    
    // 数据FIFO写使能(来自NoC Controller)
    input data_wr_en,
    // 数据FIFO满标志(反馈给NoC Controller, 用于流控)
    output data_full,
    
    // 扫描链测试接口
    input  scan_en_id, scan_in_id,
    output scan_out_id
);

    // 合并的标签总线: {col_tag, row_tag} 存入标签FIFO
    wire [ROW_TAG_WIDTH + COL_TAG_WIDTH - 1 : 0] tags_to_gin;
    // 从数据FIFO读出到GIN的数据
    wire [DATA_WIDTH - 1:0] data_from_fifo_to_gin;
    // GIN的就绪输出和内部使能
    wire ready_out, enable_in;

    // FIFO控制信号
    wire data_rd_en, data_empty;
    wire tags_rd_en, tags_empty;

    // ---- 流控制逻辑 ----
    // 使能条件: GIN就绪 AND 数据FIFO非空 AND 标签FIFO非空
    // 三者同时满足才启动数据分发
    assign enable_in = ready_out & ((~data_empty) & (~tags_empty));
    // 数据和标签同步读出
    assign data_rd_en = enable_in;
    assign tags_rd_en = enable_in;
    
    // ---- 标签FIFO ----
    // 存储{col_tag, row_tag}合并值, 与数据FIFO同步读出
    // 保证每个数据包都有正确的路由信息
    sync_fifo #(
        .R_DATA_WIDTH(ROW_TAG_WIDTH + COL_TAG_WIDTH),
        .W_DATA_WIDTH(ROW_TAG_WIDTH + COL_TAG_WIDTH),
        .FIFO_DEPTH(GIN_TAGS_FIFO_DEPTH)
    ) tags_fifo_inst (
        .clk(clk),
        .reset(reset),

        .write_request(tags_wr_en),
        .wr_data({col_tag,row_tag}),    // 高位col_tag, 低位row_tag
        .full_flag(tags_full),
        
        .read_request(tags_rd_en),
        .rd_data(tags_to_gin),
        .empty_flag(tags_empty)
    );
    
    // ---- 数据FIFO ----
    // 存储从全局缓冲区读出的数据, 与标签FIFO同步读出
    sync_fifo #(
        .R_DATA_WIDTH(DATA_WIDTH),
        .W_DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(GIN_DATA_FIFO_DEPTH)
    ) data_fifo_inst (
        .clk(clk),
        .reset(reset),

        .write_request(data_wr_en),
        .wr_data(data_in),
        .full_flag(data_full),
        
        .read_request(data_rd_en),
        .rd_data(data_from_fifo_to_gin),
        .empty_flag(data_empty)
    );
        
    // ---- GIN核心实例 ----
    // 从FIFO中取出数据和标签后送入GIN进行广播分发
    gin #(
        .DATA_WIDTH(DATA_WIDTH),
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH),
        .COL_TAG_WIDTH(COL_TAG_WIDTH),
        .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS)
    ) gin_inst (
        .clk(clk),
        .reset(reset),
        .enable_in(enable_in),
        
        .data_in(data_from_fifo_to_gin),
        // 从标签总线中拆分出row_tag(低位)和col_tag(高位)
        .row_tag(tags_to_gin [ROW_TAG_WIDTH - 1:0]),
        .col_tag(tags_to_gin [COL_TAG_WIDTH + ROW_TAG_WIDTH - 1:ROW_TAG_WIDTH]),
        
        .ready_in(ready_in),
        .scan_en_id(scan_en_id),
        .scan_in_id(scan_in_id),

        .data_out(data_out),
        .enable_out(enable_out),
        .ready_out(ready_out),
        .scan_out_id(scan_out_id)
    );
        
endmodule
