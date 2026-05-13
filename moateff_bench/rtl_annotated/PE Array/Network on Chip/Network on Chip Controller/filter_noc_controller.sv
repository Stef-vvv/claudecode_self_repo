// =============================================================================
// 模块名称: filter_noc_controller (滤波器NoC控制器)
// 功能描述: 管理滤波器(Weight)数据从全局缓冲区到PE阵列的完整数据通路。
//           包含: 索引生成器 → 地址映射器 → 全局缓冲区读 → FIFO缓冲 → 标签生成
// 数据流角色: 滤波器数据通路的总控制器。
//   filter_index_generator: 生成多维索引(4维: p*t, q*r, R, S)
//   mapper: 将多维索引映射为线性地址 addr (送往全局缓冲区读端口)
//   sync_fifo: 缓冲从全局缓冲区读出的数据(16bit输入, 64bit输出=打包到数据总线宽度)
//   filter_tag_generator: 同步生成数据路由标签(row_tag, col_tag)
// 工作流程:
//   1. start → filter_index_generator开始迭代
//   2. busy信号→re_from_glb, 发起全局缓冲区读请求
//   3. 时钟反相DFF延迟一拍 → we_to_collector → 写入FIFO
//   4. FIFO非空且下游gin_fifo不满且tags_fifo不满 → rd_from_collector读出
//   5. 读出同时驱动we_to_gin_fifo和we_to_tags_fifo, 数据+标签同步送入GIN
// =============================================================================

module filter_noc_controller
#( 
    // ---- 索引维度宽度 ----
    parameter R_WIDTH = 4,    // 滤波器高度
    parameter S_WIDTH = 6,    // 滤波器宽度
    parameter p_WIDTH = 5,    // 输出通道分块
    parameter q_WIDTH = 3,    // 输入通道分块
    parameter r_WIDTH = 2,    // 输入通道组数
    parameter t_WIDTH = 3,    // 输出通道组数
    
    // ---- FIFO参数 ----
    parameter FIFO_IN_WIDTH = 16,   // FIFO写端口宽度(全局缓冲区数据宽度)
    parameter FIFO_OUT_WIDTH = 64,  // FIFO读端口宽度(GIN数据总线宽度)
    parameter FIFO_DEPTH = 16,      // FIFO深度
      
    // ---- 标签宽度 ----
    parameter ROW_TAG_WIDTH = 4,
    parameter COL_TAG_WIDTH = 4,
    
    // ---- 地址映射参数 ----
    parameter ROW_MAJOR  = 1,       // 1=行主序, 0=列主序
    parameter ADDR_WIDTH = 20       // 线性地址位宽
) (
    input  clk,
    input  reset,
    input  start,          // 启动: from noc_controller
    output done,           // 完成: to noc_controller
    
    // 各维度尺寸
    input [R_WIDTH - 1:0] R,
    input [S_WIDTH - 1:0] S,
    input [p_WIDTH - 1:0] p,
    input [q_WIDTH - 1:0] q,
    input [r_WIDTH - 1:0] r,
    input [t_WIDTH - 1:0] t,
    
    // 全局缓冲区读地址
    output [ADDR_WIDTH-1:0] addr,
        
    // 全局缓冲区读使能(连接到filter_index_generator的busy信号)
    output re_from_glb,
    // 全局缓冲区数据输入
    input  [FIFO_IN_WIDTH - 1:0] din,
    
    // GIN FIFO接口
    input  gin_fifo_full,              // GIN数据FIFO满标志(反压)
    output we_to_gin_fifo,             // GIN数据FIFO写使能
    output [FIFO_OUT_WIDTH - 1:0] dout, // 写到GIN的数据
    
    // 标签FIFO接口
    input  tags_fifo_full,              // GIN标签FIFO满标志(反压)
    output we_to_tags_fifo,             // GIN标签FIFO写使能
    output [ROW_TAG_WIDTH - 1:0] row_tag, // 行标签
    output [COL_TAG_WIDTH - 1:0] col_tag  // 列标签
);

    // ---- 维度信息计算 ----
    // dim4 = p * t : 输出通道总数(分块×组)
    localparam DIM4_WIDTH = p_WIDTH + t_WIDTH;
    // dim3 = q * r : 输入通道总数(分块×组)
    localparam DIM3_WIDTH = q_WIDTH + r_WIDTH;
    localparam DIM2_WIDTH = R_WIDTH;  // dim2 = R : 滤波器行数
    localparam DIM1_WIDTH = S_WIDTH;  // dim1 = S : 滤波器列数
    
    // idx宽度与dim相同(索引和维度用相同位宽)
    localparam IDX4_WIDTH = p_WIDTH + t_WIDTH;
    localparam IDX3_WIDTH = q_WIDTH + r_WIDTH;
    localparam IDX2_WIDTH = R_WIDTH;
    localparam IDX1_WIDTH = S_WIDTH;
    
    // 维度信号
    wire [DIM4_WIDTH - 1:0] dim4;
    wire [DIM3_WIDTH - 1:0] dim3;
    wire [DIM2_WIDTH - 1:0] dim2;
    wire [DIM1_WIDTH - 1:0] dim1;
    
    assign dim4 = p * t;     // 输出通道总数 = p × t
    assign dim3 = q * r;     // 输入通道总数 = q × r
    assign dim2 = R;         // 滤波器行数
    assign dim1 = S;         // 滤波器列数
    
    // 索引信号
    wire [IDX4_WIDTH - 1:0] idx4;   // filter_index : 输出通道索引
    wire [IDX3_WIDTH - 1:0] idx3;   // channel_index: 输入通道索引
    wire [IDX2_WIDTH - 1:0] idx2;   // row_index    : 行索引
    wire [IDX1_WIDTH - 1:0] idx1;   // col_index    : 列索引
    
    // ---- FIFO流控信号 ----
    wire collector_full;
    wire collector_empty;
    wire we_to_collector;        // 从全局缓冲区写入内部FIFO
    wire rd_from_collector;      // 从内部FIFO读到GIN
       
    // 读出条件: FIFO非空 AND GIN数据FIFO未满 AND GIN标签FIFO未满
    // 三路同步: 数据+标签同时写入GIN
    assign rd_from_collector = (~collector_empty) & (~gin_fifo_full) & (~tags_fifo_full);
    assign we_to_gin_fifo = rd_from_collector;
    assign we_to_tags_fifo = we_to_gin_fifo;
    
    // 时钟反相DFF: 延迟一拍
    // re_from_glb(clk上升沿) → 数据需要1拍才能从全局缓冲区返回
    // ~clk触发 → 在数据返回时采样
    flopr #(.DATA_WIDTH(1)) dff (
        .clk(~clk),
        .reset(reset),
        .d(re_from_glb),
        .q(we_to_collector)
    );
        
    // ---- 滤波器索引生成器 ----
    // 生成 4 维索引: filter_index(输出通道), channel_index(输入通道),
    //                 row_index(行), col_index(列)
    // await连接FIFO满标志, 反压时暂停索引更新
    // busy直接作为re_from_glb, 每个busy周期发起一次全局缓冲区读
    filter_index_generator #(
        .R_WIDTH(R_WIDTH),
        .S_WIDTH(S_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),
        .r_WIDTH(r_WIDTH),
        .t_WIDTH(t_WIDTH)
    ) filter_index_generator_inst (
        .clk(~clk),           // 反相时钟: 与FIFO写入同步
        .reset(reset),
        
        .start(start),
        .await(collector_full),  // FIFO满时暂停
        .busy(re_from_glb),     // 忙碌 → 读请求
        .done(done),
        
        .R(R),
        .S(S),
        .p(p),
        .q(q),
        .r(r),
        .t(t),
        
        .filter_index(idx4),
        .channel_index(idx3),
        .row_index(idx2),
        .col_index(idx1)
    );
    
    // ---- 地址映射器 ----
    // 将4维索引映射为线性地址 addr = idx4*dim3*dim2*dim1 + idx3*dim2*dim1 + idx2*dim1 + idx1
    // 滤波器数据按 (p*t) × (q*r) × R × S 四维数组存储在全局缓冲区中
    mapper #(
        .DIM4_WIDTH(DIM4_WIDTH),
        .DIM3_WIDTH(DIM3_WIDTH),
        .DIM2_WIDTH(DIM2_WIDTH),
        .DIM1_WIDTH(DIM1_WIDTH),
        
        .IDX4_WIDTH(IDX4_WIDTH),
        .IDX3_WIDTH(IDX3_WIDTH),
        .IDX2_WIDTH(IDX2_WIDTH),
        .IDX1_WIDTH(IDX1_WIDTH),
        
        .ROW_MAJOR(ROW_MAJOR),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) filter_mapper_inst (
        .dim4(dim4),
        .dim3(dim3),
        .dim2(dim2),
        .dim1(dim1),
        
        .idx4(idx4),
        .idx3(idx3),
        .idx2(idx2),
        .idx1(idx1),
        
        .addr(addr)
    );

    // ---- 内部缓冲FIFO ----
    // 写宽度=FIFO_IN_WIDTH(全局缓冲区数据宽度16bit)
    // 读宽度=FIFO_OUT_WIDTH(GIN总线宽度64bit)
    // 实现宽度转换: 每4个16bit数据打包为64bit输出
    sync_fifo #(
        .R_DATA_WIDTH(FIFO_OUT_WIDTH),
        .W_DATA_WIDTH(FIFO_IN_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) filter_fifo_inst (
        .clk(clk),
        .reset(reset),
        
        .write_request(we_to_collector),
        .wr_data(din),    
        .read_request(rd_from_collector),
        .rd_data(dout),    
        
        .full_flag(collector_full), 
        .empty_flag(collector_empty)
    );
    
    // ---- 标签生成器 ----
    // 与数据同频生成路由标签, 保证每个数据包有正确的目标PE坐标
    filter_tag_generator #(
        .R_WIDTH(R_WIDTH),
        .r_WIDTH(r_WIDTH),
        .t_WIDTH(t_WIDTH),
        
        .ROW_TAG_WIDTH(ROW_TAG_WIDTH),
        .COL_TAG_WIDTH(COL_TAG_WIDTH)
    ) filter_tag_generator_inst (
        .clk(clk),
        .reset(reset),
        .start(start),
        .enable(rd_from_collector),       // 与数据读出同步
        
        .R(R),
        .r(r),
        .t(t),
        
        .row_tag(row_tag),
        .col_tag(col_tag)
    );
    
endmodule
