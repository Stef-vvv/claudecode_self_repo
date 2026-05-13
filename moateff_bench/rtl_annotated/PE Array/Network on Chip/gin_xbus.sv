// =============================================================================
// 模块名称: gin_xbus (GIN Crossbar Bus / 全局输入网络列交叉开关)
// 功能描述: 将行选出的数据通过col_tag广播到该行各列PE。
//           实例化NUM_OF_COLS个gin_mcc, 每个MCC对应一列。
//           只有col_tag匹配的列MCC才放行数据。
// 数据流角色: GIN行→列分发层 —— 接收行级MCC选出的row_data_out[i],
//           在一行内的各列中根据col_tag再选通一次。
// =============================================================================

module gin_xbus #(
    // 数据位宽
    parameter int DATA_WIDTH = 64, 
    // 列标签位宽
    parameter int COL_TAG_WIDTH = 4,
    // 一行中的列数(PE阵列宽度)
    parameter int NUM_OF_COLS = 14
) (
    // 输入数据(来自行级MCC)
    input logic [DATA_WIDTH - 1:0] data_in,
    // 列标签: 指示目标列
    input logic [COL_TAG_WIDTH - 1:0] col_tag,

    // 该行各列PE的就绪信号: ready_in[col]
    input logic [0:NUM_OF_COLS - 1] ready_in,
    // 时钟/复位/使能(来自行级MCC)
    input logic clk, reset, enable_in,
    // 扫描链测试接口
    input logic scan_en_id, scan_in_id,

    // 输出数据到该行各列PE: data_out[col]
    output logic [DATA_WIDTH - 1:0] data_out [0:NUM_OF_COLS - 1],
    // 输出使能到各列: enable_out[col]
    output logic [0:NUM_OF_COLS - 1] enable_out,
    // 该XBus的就绪输出
    output logic ready_out,
    // 扫描链测试输出
    output logic scan_out_id
);

    // 扫描链布线: 每列一个MCC消耗1个扫描位
    // scan_in → MCC_col0 → MCC_col1 → ... → MCC_col(N-1) → scan_out
    wire [0 : NUM_OF_COLS] scan_w;
    assign scan_w[0] = scan_in_id;
    assign scan_out_id = scan_w[NUM_OF_COLS];
    
    // =========================================================================
    // 生成块: 为每一列实例化一个gin_mcc
    // 循环变量i: 0 ~ NUM_OF_COLS-1
    // 原理: 行级已经做了粗选, 这里按列标签做细选
    //       只有col_tag == 该列MCC的scan ID时, 数据才输出到该列
    // =========================================================================
    genvar i;
    generate
        for (i = 0; i < NUM_OF_COLS; i = i + 1) begin : MCC_INSTANCE
            gin_mcc #(
                .DATA_WIDTH(DATA_WIDTH),
                .TAG_WIDTH(COL_TAG_WIDTH)
            ) mcc_inst (
                .data_in(data_in),         // 整行数据输入(所有列共享)
                .tag(col_tag),             // 列标签比较
                .clk(clk),
                .reset(reset),
                .ready_in(ready_in[i]),    // 第i列PE的就绪信号
                .enable_in(enable_in),
                .scan_en_id(scan_en_id),//
                .scan_in_id(scan_w[i]),    // 扫描链级联
                .ready_out(ready_out[i]),
                .enable_out(enable_out[i]),
                .data_out(data_out[i]),    // 输出到第i列PE
                .scan_out_id(scan_w[i+1])  // 传递到下一列
            );
        end
    endgenerate

endmodule
