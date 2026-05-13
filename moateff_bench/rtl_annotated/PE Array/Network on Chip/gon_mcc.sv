// =============================================================================
// 模块名称: gon_mcc (GON Multi-Cast Controller / 全局输出网络多播控制器)
// 功能描述: GON的标签匹配选通单元。与gin_mcc相似但输出行为不同:
//           匹配时驱动data_out为data_in; 不匹配时输出高阻态({DATA_WIDTH{1'bz}})。
//           这样多个gon_mcc可以共享同一根data_out三态总线。
// 数据流角色: GON的最小选通单元, 用于从PE阵列收集数据到共享输出总线。
// 与gin_mcc的关键区别:
//   1. 不匹配时输出 'bz (高阻) 而非 'b0 —— 允许多个MCC共享总线
//   2. data_out是inout wire类型, 支持三态驱动
// =============================================================================

module gon_mcc #(
    // 数据位宽
    parameter int DATA_WIDTH = 64, 
    // 标签位宽
    parameter int TAG_WIDTH = 4
) (
    // 输入数据
    input logic [DATA_WIDTH - 1:0] data_in,
    // 目标标签
    input logic [TAG_WIDTH - 1:0] tag,
    // 下游就绪
    input logic ready_in,
    // 时钟/复位/使能
    input logic clk, reset, enable_in,
    // 扫描链测试接口
    input logic scan_en_id, scan_in_id,

    // 输出数据: 匹配时驱动data_in, 不匹配时高阻态('bz)
    // 'bz允许总线共享, 这是GON与GIN的核心区别
    output logic [DATA_WIDTH - 1:0] data_out,
    // 就绪输出
    output logic ready_out,
    // 使能输出
    output logic enable_out,
    // 扫描链测试输出
    output logic scan_out_id
);

    // 标签匹配标志
    logic equal_tag;
    // 中间使能信号
    logic enable_mid;
    // 扫描链中存储的ID
    logic [TAG_WIDTH - 1:0] q_id;
    
    // 标签比较
    assign equal_tag = (q_id == tag);
    // 就绪输出: 下游就绪 OR 标签不匹配(跳过)
    assign ready_out = ready_in | (!equal_tag);
    // 中间使能: 三重条件 AND
    assign enable_mid = enable_in & ready_in & equal_tag;
    // 使能传递
    assign enable_out = enable_mid;
    // 数据输出: 【与GIN的关键区别】
    // 匹配时→输出数据, 不匹配时→高阻态('bz)
    // 这样多个gon_mcc可以共享一根data_out线, 只有匹配的那个驱动总线
    assign data_out = enable_mid ? data_in : {DATA_WIDTH{1'bz}};
    
    // 扫描链: 存储硬件ID
    scan_ff_Nbit #(.DATA_WIDTH(TAG_WIDTH)) scan_ff_Nbit_inst (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en_id),
        .scan_in(scan_in_id),
        .q(q_id),
        .scan_out(scan_out_id)
    );

endmodule
