// =============================================================================
// 模块名称: gon_xbus (GON Crossbar Bus / 全局输出网络列交叉开关)
// 功能描述: GON的列级数据收集器。实例化NUM_OF_COLS个gon_mcc,
//           从PE阵列该行的各列数据中按col_tag选出一列, 汇总到一根data_out总线。
// 数据流角色: GON列级收集层 —— 该行的所有列PE数据输入, 按col_tag选通一列,
//           输出到该行的gon_mcc进一步做行级选通。
// 与gin_xbus的关键区别: 数据流向相反, 输出是共享的inout总线,
//           各列gon_mcc的输出通过data_out三态总线汇聚。
// =============================================================================

module gon_xbus #(
    // 数据位宽
    parameter int DATA_WIDTH = 64, 
    // 列标签位宽
    parameter int COL_TAG_WIDTH = 4,
    // 列数
    parameter int NUM_OF_COLS = 14
) (
    // 输入数据: 该行各列PE的data_out, data_in[col]
    input logic [DATA_WIDTH - 1:0] data_in [0:NUM_OF_COLS - 1],
    // 列标签: 选择目标列
    input logic [COL_TAG_WIDTH - 1:0] col_tag,

    // 该行各列PE的ready信号
    input logic [0:NUM_OF_COLS - 1] ready_in,
    // 时钟/复位/使能
    input logic clk, reset, enable_in,
    // 扫描链测试接口
    input logic scan_en_id, scan_in_id,

    // 共享输出总线: inout wire, 各列gon_mcc的输出汇聚于此
    inout wire [DATA_WIDTH - 1:0] data_out,
    // 输出使能到各列PE
    output logic [0:NUM_OF_COLS - 1] enable_out,
    // XBus就绪输出
    output logic ready_out,
    // 扫描链测试输出
    output logic scan_out_id
);

    // 扫描链布线: 每列MCC消耗1位
    wire [0 : NUM_OF_COLS] scan_w;
    assign scan_w[0] = scan_in_id;
    assign scan_out_id = scan_w[NUM_OF_COLS];
        
    // =========================================================================
    // 生成块: 为每一列实例化gon_mcc
    // 所有列的输出通过data_out三态总线汇聚 → 行MCC进一步选择
    // 循环变量i: 0 ~ NUM_OF_COLS-1
    // =========================================================================
    genvar i;
    generate
        for (i = 0; i < NUM_OF_COLS; i = i + 1) begin : MCC_INSTANCE
            gon_mcc #(
                .DATA_WIDTH(DATA_WIDTH),
                .TAG_WIDTH(COL_TAG_WIDTH)
            ) mcc_inst (
                .data_in(data_in[i]),      // 第i列PE的数据
                .tag(col_tag),             // 列标签匹配
                .clk(clk),
                .reset(reset),
                .ready_in(ready_in[i]),    // 第i列PE就绪
                .enable_in(enable_in),
                .scan_en_id(scan_en_id),//
                .scan_in_id(scan_w[i]),//
                .ready_out(ready_out[i]),
                .enable_out(enable_out[i]),
                .data_out(data_out),       // 共享输出总线
                .scan_out_id(scan_w[i+1])//
            );
        end
    endgenerate
    
endmodule
