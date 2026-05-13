// =============================================================================
// 模块名称: gin_mcc (GIN Multi-Cast Controller / 全局输入网络多播控制器)
// 功能描述: 标签匹配选通单元。将输入TAG与扫描链中存储的ID比较,
//           匹配且使能且下游就绪时, 数据通过; 否则输出0。
// 数据流角色: GIN的最小选通单元, 用作行选(MCC at row level)或列选(MCC in XBus)。
//           一个MCC实例对应一行或一列的一个广播端点。
// 工作原理:
//   1. scan_ff_Nbit存储该实例的硬件ID (q_id)
//   2. equal_tag = (q_id == tag): 标签匹配检查
//   3. enable_mid = enable_in & ready_in & equal_tag: 三重条件同时满足才放行
//   4. ready_out = ready_in | (!equal_tag): 不匹配时直接反馈就绪(跳过)
// =============================================================================

module gin_mcc #(
    // 数据位宽
    parameter int DATA_WIDTH = 64, 
    // 标签位宽(行标签或列标签)
    parameter int TAG_WIDTH = 4
) (
    // 输入数据总线
    input logic [DATA_WIDTH - 1:0] data_in,
    // 目标标签: 与内部ID比较
    input logic [TAG_WIDTH - 1:0] tag,
    // 下游就绪: 该行/列的PE是否可以接收数据
    input logic ready_in,
    // 时钟/复位/全局使能
    input logic clk, reset, enable_in,
    // 扫描链测试接口
    input logic scan_en_id, scan_in_id,

    // 输出数据: 匹配时=data_in, 否则=0
    output logic [DATA_WIDTH - 1:0] data_out,
    // 就绪输出: 向上游反馈本节点是否准备好
    output logic ready_out,
    // 使能传递给下游
    output logic enable_out,
    // 扫描链测试输出
    output logic scan_out_id
);

    // 标签匹配标志
    logic equal_tag;
    // 中间使能信号: 使能 & 就绪 & 标签匹配
    logic enable_mid;
    // 本实例的扫描链ID(硬件地址)
    logic [TAG_WIDTH - 1:0] q_id;
    
    // 标签比较: 扫描链ID == 输入标签?
    assign equal_tag = (q_id == tag);
    // 就绪输出: 下游就绪 OR 标签不匹配 (不匹配时直接放行, 不阻塞流水线)
    assign ready_out = ready_in | (!equal_tag);
    // 中间使能: 三重条件 AND —— 全局使能 & 下游就绪 & 标签匹配
    assign enable_mid = enable_in & ready_in & equal_tag;
    // 使能传递
    assign enable_out = enable_mid;
    // 数据输出: 使能有效时传递数据, 否则输出全0
    assign data_out = enable_mid ? data_in : {DATA_WIDTH{1'b0}};
    
    // 扫描链: 存储本实例的硬件ID
    // 通过scan_ff串联, 在测试模式(scan_en_id=1)下可移位配置ID
    scan_ff_Nbit #(.DATA_WIDTH(TAG_WIDTH)) scan_ff_Nbit_inst (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en_id),
        .scan_in(scan_in_id),
        .q(q_id),
        .scan_out(scan_out_id)
    );

endmodule
