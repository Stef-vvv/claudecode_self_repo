// =============================================================================
// 模块名称: gon_wrapper (GON 包装器)
// 功能描述: 在GON(全局输出网络)基础上增加标签FIFO和数据FIFO进行流量缓冲。
//           标签先入标签FIFO, GON收集数据后写入数据FIFO, 下游从数据FIFO读出。
// 数据流角色: GON的缓冲出口 —— GON从PE阵列收集数据写入数据FIFO,
//           下游(opsum controller)从数据FIFO读取。标签FIFO保证输出数据有正确的路由标签。
// 与gin_wrapper的差别: 数据流向相反 —— 
//   gin_wrapper: 数据从FIFO→GIN→PE (输出)
//   gon_wrapper: PE→GON→FIFO (收集)
// =============================================================================

module gon_wrapper
#(
    // 数据位宽
    parameter DATA_WIDTH     = 64,
    // 行标签位宽
    parameter ROW_TAG_WIDTH  = 4,
    // 列标签位宽
    parameter COL_TAG_WIDTH  = 4,
    // PE阵列行数
    parameter NUM_OF_ROWS    = 12,
    // PE阵列列数
    parameter NUM_OF_COLS    = 14,
    // 数据FIFO深度
    parameter GON_DATA_FIFO_DEPTH = 4096,
    // 标签FIFO深度
    parameter GON_TAGS_FIFO_DEPTH = 4096  
)(
    input clk,
    input reset,
    
    // 行标签输入
    input [ROW_TAG_WIDTH - 1:0] row_tag,
    // 列标签输入
    input [COL_TAG_WIDTH - 1:0] col_tag,

    // PE阵列输入数据: 2D数组
    input  [DATA_WIDTH - 1:0] data_in  [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS - 1],   
    // 输出数据(从FIFO读出)
    output [DATA_WIDTH - 1:0] data_out,
    
    // PE阵列ready信号
    input  [0:NUM_OF_COLS - 1] ready_in   [0:NUM_OF_ROWS - 1], 
    // GON输出使能到PE
    output [0:NUM_OF_COLS - 1] enable_out [0:NUM_OF_ROWS - 1],     
    
    // 标签FIFO控制: 写使能(来自Controller), 满标志(反馈)
    input  tags_wr_en,
    output tags_full,
    
    // 数据FIFO控制: 读使能(来自下游opsum controller), 空标志(反馈)
    input  data_rd_en,
    output data_empty,
    
    // 扫描链测试接口
    input  scan_en_id, scan_in_id,
    output scan_out_id
);

    // 合并标签总线
    wire [ROW_TAG_WIDTH + COL_TAG_WIDTH - 1 : 0] tags_to_gon;
    // GON收集的数据
    wire [DATA_WIDTH - 1:0] dout_from_gon;
    // GON就绪和使能
    wire ready_out, enable_in;

    // FIFO控制信号
    wire data_wr_en, data_full;
    wire tags_rd_en, tags_empty;
    
    // ---- 流控制逻辑 ----
    // 使能条件: GON就绪 AND 数据FIFO未满 AND 标签FIFO非空
    // 三者同时满足才能从GON收集数据并写入FIFO
    assign enable_in = ready_out & ((~data_full) & (~tags_empty));
    // GON数据使能 → 写入数据FIFO
    assign data_wr_en = enable_in;
    // 标签同步读出
    assign tags_rd_en = enable_in;

    // ---- 标签FIFO ----
    // 存储{col_tag, row_tag}, 与GON收集同步读出
    // 保证每个收集到的数据有正确的路由标签记录
    sync_fifo #(
        .R_DATA_WIDTH(ROW_TAG_WIDTH + COL_TAG_WIDTH),
        .W_DATA_WIDTH(ROW_TAG_WIDTH + COL_TAG_WIDTH),
        .FIFO_DEPTH(GON_TAGS_FIFO_DEPTH)
    ) tags_fifo_inst (
        .clk(clk),
        .reset(reset),

        .write_request(tags_wr_en),
        .wr_data({col_tag,row_tag}),
        .full_flag(tags_full),
        
        .read_request(tags_rd_en),
        .rd_data(tags_to_gon),
        .empty_flag(tags_empty)
    );
      
    // ---- 数据FIFO ----
    // 存储GON收集的数据, 供下游opsum controller读取
    sync_fifo #(
        .R_DATA_WIDTH(DATA_WIDTH),
        .W_DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(GON_DATA_FIFO_DEPTH)
    ) data_fifo_inst (
        .clk(clk),
        .reset(reset),

        .write_request(data_wr_en),
        .wr_data(dout_from_gon),     // GON收集的数据写入FIFO
        .full_flag(data_full),
        
        .read_request(data_rd_en),
        .rd_data(data_out),          // 下游读取
        .empty_flag(data_empty)
    );
        
    // ---- GON核心实例 ----
    gon #(
        .DATA_WIDTH(DATA_WIDTH),
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH),
        .COL_TAG_WIDTH(COL_TAG_WIDTH),
        .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS)
    ) gon_inst (
        .clk(clk),
        .reset(reset),
        .enable_in(enable_in),
        
        .data_in(data_in),
        // 从标签FIFO拆分row_tag和col_tag
        .row_tag(tags_to_gon [ROW_TAG_WIDTH - 1:0]),
        .col_tag(tags_to_gon [COL_TAG_WIDTH + ROW_TAG_WIDTH - 1:ROW_TAG_WIDTH]),        
        
        .ready_in(ready_in),
        .scan_en_id(scan_en_id),
        .scan_in_id(scan_in_id),
        
        
        .data_out(dout_from_gon),
        .enable_out(enable_out),
        .ready_out(ready_out),
        .scan_out_id(scan_out_id)
    );
        
endmodule
