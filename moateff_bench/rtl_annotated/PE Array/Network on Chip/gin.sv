// =============================================================================
// 模块名称: gin (Global Input Network / 全局输入网络)
// 功能描述: 将全局缓冲区(Global Buffer)的数据通过行选和列选分发到PE阵列的各行各列。
// 数据流角色: 输入分发网络 —— 一根数据总线进来，通过两级MCC(Multi-Cast Controller)
//           行级选通 + XBus列级选通，广播到 NUM_OF_ROWS × NUM_OF_COLS 的PE阵列。
// 架构: 层次化分发 —— 第一层(gin_mcc): 按row_tag选通行; 第二层(gin_xbus): 按col_tag选通列。
//       每行一个MCC实例 + 一个XBus实例, 共NUM_OF_ROWS行。
// =============================================================================

module gin #(
    // 数据位宽, 默认64位(对应8个8-bit数据打包)
    parameter int DATA_WIDTH = 64,
    // 行标签位宽(用于行地址匹配)
    parameter int ROW_TAG_WIDTH = 4,
    // 列标签位宽(用于列地址匹配)
    parameter int COL_TAG_WIDTH = 4,
    // PE阵列的行数
    parameter int NUM_OF_ROWS = 12,
    // PE阵列的列数
    parameter int NUM_OF_COLS = 14
) (
    // 全局时钟与复位
    input logic clk, reset,
    // 全局使能: 高有效时允许数据流动
    input logic enable_in,
    // 输入数据总线
    input logic [DATA_WIDTH - 1:0] data_in,
    // 行标签: 指示当前数据目标行
    input logic [ROW_TAG_WIDTH - 1:0] row_tag,
    // 列标签: 指示当前数据目标列
    input logic [COL_TAG_WIDTH - 1:0] col_tag,

    // 每个PE单元的ready信号: ready_in[row][col]=1表示该PE可以接收数据
    // 2D数组: [0:NUM_OF_ROWS-1][0:NUM_OF_COLS-1]
    input logic [0:NUM_OF_COLS - 1] ready_in [0:NUM_OF_ROWS - 1],

    // 扫描链测试接口
    input logic scan_en_id, scan_in_id,

    // 输出数据到PE阵列: 2D数组, 每个元素是DATA_WIDTH位宽
    output logic [DATA_WIDTH - 1:0] data_out [0:NUM_OF_ROWS - 1][0:NUM_OF_COLS - 1],
    // 输出使能到每个PE: 对应data_out有效
    output logic [0:NUM_OF_COLS - 1] enable_out [0:NUM_OF_ROWS - 1],
    // 全局就绪输出: 所有行的MCC都就绪时置1
    output logic ready_out,
    // 扫描链测试输出
    output logic scan_out_id
);

    // ---- 内部信号 ----
    // 行级数据输出: MCC选出后整行数据
    logic [DATA_WIDTH - 1:0] row_data_out [0:NUM_OF_ROWS - 1];
    // 行级使能输出
    logic row_enable_out [0:NUM_OF_ROWS - 1];
    // 行级内部就绪: 用列级ready的AND归约得到, 表示该行所有列都就绪
    logic internal_ready [0:NUM_OF_ROWS - 1];
    // 每行MCC的就绪输出
    logic [0:NUM_OF_ROWS - 1] mcc_ready ;
    // 每行XBus的就绪输出数组: xbuses_ready[row][col]
    logic [0:NUM_OF_COLS - 1] xbuses_ready [0:NUM_OF_ROWS - 1];

    // 扫描链布线: 每行消耗2个扫描位(MCC + XBus)
    // 扫描链顺序: scan_in → MCC_row0 → XBus_row0 → MCC_row1 → XBus_row1 → ... → scan_out
    logic [0 : NUM_OF_ROWS*2] scan_w;
    assign scan_w[0] = scan_in_id;
    assign scan_out_id = scan_w[NUM_OF_ROWS*2];

    // 全局就绪: 所有行的MCC都就绪 (AND归约)
    assign  ready_out = & mcc_ready;

    // =========================================================================
    // 生成块: 为每一行实例化一个MCC + 一个XBus
    // 循环变量i: 0 ~ NUM_OF_ROWS-1, 对应PE阵列的每一行
    // =========================================================================
    genvar i;
    generate
        for (i = 0; i < NUM_OF_ROWS; i = i + 1) begin : ROW_MCC_XBUS

            // 行内部就绪: 该行所有列的XBus都就绪
            assign internal_ready[i] = &xbuses_ready[i];

            // ---- 行级MCC实例 ----
            // 功能: 根据row_tag选通目标行, 只让匹配行的MCC接收数据
            gin_mcc #( 
                .DATA_WIDTH(DATA_WIDTH),
                .TAG_WIDTH(ROW_TAG_WIDTH)
            ) mcc_inst (
                .data_in(data_in),              // 全局输入数据
                .tag(row_tag),                  // 行标签匹配
                .clk(clk),
                .reset(reset),
                .ready_in(internal_ready[i]),   // 该行所有列就绪则MCC可接收
                .enable_in(enable_in),
                .scan_en_id(scan_en_id),//
                .scan_in_id(scan_w[i+i]),       // 扫描链位置: 偶数位
                .ready_out(mcc_ready[i]),
                .enable_out(row_enable_out[i]),
                .data_out(row_data_out[i]),     // 输出到该行的XBus
                .scan_out_id(scan_w[i+i+1])     // 扫描链位置: 奇数位
            );

            // ---- 列级XBus实例 ----
            // 功能: 将行选出的数据通过col_tag分发到该行的各列PE
            gin_xbus #( 
                .DATA_WIDTH(DATA_WIDTH),
                .COL_TAG_WIDTH(COL_TAG_WIDTH),
                .NUM_OF_COLS(NUM_OF_COLS)
            ) xbus_inst (
                .data_in(row_data_out[i]),      // 来自行MCC的数据
                .col_tag(col_tag),              // 列标签匹配
                .ready_in(ready_in[i]),         // 该行各列的PE就绪信号
                .clk(clk),
                .reset(reset),
                .enable_in(row_enable_out[i]),  // 行MCC使能传递
                .scan_en_id(scan_en_id),//
                .scan_in_id(scan_w[i+i+1]),     // 扫描链: 行MCC扫描输出作为XBus扫描输入
                .data_out(data_out[i]),         // 最终输出到该行各列PE
                .ready_out(xbuses_ready[i]),
                .enable_out(enable_out[i]), 
                .scan_out_id(scan_w[i+i+2])     // 传递给下一行的MCC
            );
        end
    endgenerate

endmodule
