// =============================================================================
// 模块名称: gon (Global Output Network / 全局输出网络)
// 功能描述: GIN的反向网络 —— 从PE阵列收集输出数据汇总到全局缓冲区。
//           通过行选MCC + XBus列选, 每次选通一行一列的数据输出到data_out总线。
// 数据流角色: 输出收集网络 —— PE阵列数据通过两级MCC(XBus列选 + MCC行选)汇聚到一根输出总线。
//           与GIN的关键区别: data_out是inout wire(三态总线), 允许多个MCC共享一根输出线。
// 架构: 层次化收集 —— 第一层(gon_xbus): 按col_tag选出目标列的数据;
//       第二层(gon_mcc): 按row_tag选出目标行的数据到共享总线。
// =============================================================================

module gon #(
    // 数据位宽
    parameter int DATA_WIDTH = 64, 
    // 行标签位宽
    parameter int ROW_TAG_WIDTH = 4,
    // 列标签位宽
    parameter int COL_TAG_WIDTH = 4,
    // PE阵列行数
    parameter int NUM_OF_ROWS = 12,
    // PE阵列列数
    parameter int NUM_OF_COLS = 14
) (
    // 时钟/复位/使能
    input logic clk, reset, enable_in,
    // PE阵列输入数据: 2D数组 data_in[row][col]
    input logic [DATA_WIDTH - 1:0] data_in [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS - 1],
    // 行标签: 选择目标行
    input logic [ROW_TAG_WIDTH - 1:0] row_tag,
    // 列标签: 选择目标列
    input logic [COL_TAG_WIDTH - 1:0] col_tag,

    // PE阵列各单元的ready信号
    input logic [0:NUM_OF_COLS - 1] ready_in [0:NUM_OF_ROWS - 1],

    // 扫描链测试接口
    input logic scan_en_id, scan_in_id,

    // 输出数据: inout三态总线, 多个MCC共享
    // 与GIN的区别: GIN是output logic(每个PE独立输出), GON是inout wire(共享总线)
    inout wire [DATA_WIDTH - 1:0] data_out,
    // 输出使能到PE阵列
    output logic [0:NUM_OF_COLS - 1] enable_out [0:NUM_OF_ROWS - 1],
    // 全局就绪
    output logic ready_out,
    // 扫描链测试输出
    output logic scan_out_id
);

    // ---- 内部信号 ----
    // 行级数据: XBus选出后该行目标列的数据
    wire [DATA_WIDTH - 1:0] row_data_out [0:NUM_OF_ROWS - 1];
    // 行级使能
    logic row_enable_out [0:NUM_OF_ROWS - 1];
    // 行级内部就绪
    logic internal_ready [0:NUM_OF_ROWS - 1];
    // 各MCC就绪
    logic [0:NUM_OF_ROWS - 1] mcc_ready;
    // 各XBus就绪
    logic [0:NUM_OF_COLS - 1] xbuses_ready [0:NUM_OF_ROWS - 1];
    
    // 全局就绪: 所有MCC都就绪
    assign ready_out = &mcc_ready;
    
    // 扫描链布线: 每行MCC+XBus共2位
    logic [0 : NUM_OF_ROWS*2] scan_w;
    assign scan_w[0] = scan_in_id;
    assign scan_out_id = scan_w[NUM_OF_ROWS*2];
    
    // =========================================================================
    // 生成块: 为每一行实例化XBus(列选) + MCC(行选)
    // 注意: 与GIN顺序相反! GON先做列选(XBus), 再做行选(MCC)
    // 这样列XBus从各列PE读数据, 选出一列; 行MCC从各列XBus中选出目标行
    // =========================================================================
    genvar i;
    generate
        for (i = 0; i < NUM_OF_ROWS; i = i + 1) begin : ROW_MCC_XBUS
        
            // 行内就绪: 该行所有列XBus都就绪
            assign internal_ready[i] = &xbuses_ready[i];  

            // ---- 行级MCC实例 ----
            // 功能: 将XBus选出的row_data_out[i]输出到共享data_out总线
            // 只有当row_tag匹配时才驱动data_out
            gon_mcc #( 
                .DATA_WIDTH(DATA_WIDTH),
                .TAG_WIDTH(ROW_TAG_WIDTH)
            ) mcc_inst (
                .data_in(row_data_out[i]),         // 来自该行XBus的数据
                .tag(row_tag),                     // 行标签比较
                .clk(clk),
                .reset(reset),
                .ready_in(internal_ready[i]), 
                .enable_in(enable_in),
                .scan_en_id(scan_en_id),//
                .scan_in_id(scan_w[i+i]),//
                .ready_out(mcc_ready[i]),
                .enable_out(row_enable_out[i]),
                .data_out(data_out),               // 输出到共享总线(inout)
                .scan_out_id(scan_w[i+i+1])//
            );
    
            // ---- 列级XBus实例 ----
            // 功能: 从PE阵列该行的各列数据中按col_tag选出一列
            gon_xbus #( 
                .DATA_WIDTH(DATA_WIDTH),
                .COL_TAG_WIDTH(COL_TAG_WIDTH),
                .NUM_OF_COLS(NUM_OF_COLS)
            ) xbus_inst (
                .data_in(data_in[i]),              // 该行各列PE的数据
                .col_tag(col_tag),                 // 列标签比较
                .ready_in(ready_in[i]),
                .clk(clk),
                .reset(reset),
                .enable_in(row_enable_out[i]),
                .scan_en_id(scan_en_id),//
                .scan_in_id(scan_w[i+i+1]),//
                .data_out(row_data_out[i]),        // 选出后传到行MCC
                .ready_out(xbuses_ready[i]),
                .enable_out(enable_out[i]),
                .scan_out_id(scan_w[i+i+2])//
            );
        end
    endgenerate

endmodule
