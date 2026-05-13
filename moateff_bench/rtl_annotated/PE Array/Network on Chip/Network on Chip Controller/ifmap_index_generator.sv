// =============================================================================
// 模块名称: ifmap_index_generator (输入特征图索引生成器)
// 功能描述: 生成输入特征图(Ifmap)存储器的4维索引, 驱动从全局缓冲区读取ifmap数据。
//           实现 nested-loop 迭代:
//             for n (批大小) for W (宽度) for q (输入通道分块) for D (高度) for r (通道复用)
//               每个循环步进一次 (单层循环, 无内层4次子循环)
// 数据流角色: ifmap_noc_controller 的地址生成引擎,
//           输出 ifmap_index(n), channel_index(q+r*q), row_index(D), col_index(W)。
// 与filter_index_generator的区别:
//   - 无i=4内循环: 每个enable周期更新一次索引(而非4次)
//   - 无lock机制, 无OUTER_LOOP/INNER_LOOP分割: 采用单一LOOPING状态
//   - 顺序: D→W→q→r→n (与filter的R→S→q→r→p→t不同)
// =============================================================================

module ifmap_index_generator
#( 
    // Ifmap高度位宽
    parameter D_WIDTH = 8,
    // Ifmap宽度位宽
    parameter W_WIDTH = 8,
    // 批大小位宽
    parameter n_WIDTH = 3,
    // 输入通道分块位宽
    parameter q_WIDTH = 3,
    // 通道复用组数位宽
    parameter r_WIDTH = 2
) (
    input clk,
    input reset,
    input start,
    input await,           // 反压信号: 下游FIFO满时暂停
    
    output reg busy,       // 忙标志: 同时驱动读请求
    output reg done,       // 完成标志

    // 各维度最大尺寸
    input [D_WIDTH - 1:0] D,    // Ifmap高度
    input [W_WIDTH - 1:0] W,    // Ifmap宽度
    input [n_WIDTH - 1:0] n,    // 批大小
    input [q_WIDTH - 1:0] q,    // 输入通道分块
    input [r_WIDTH - 1:0] r,    // 通道组数

    // ifmap_index: 批索引 (n维度)
    output reg [n_WIDTH - 1:0] ifmap_index,
    // channel_index: q + r * q (在q×r平面内的线性通道索引)
    output reg [q_WIDTH + r_WIDTH - 1:0] channel_index,
    // row_index: 行索引 (D维度)
    output reg [D_WIDTH - 1:0] row_index,
    // col_index: 列索引 (W维度)  
    output reg [W_WIDTH - 1:0] col_index    
);
    
    // FSM状态
    // IDLE → LOOPING(单次步进) → DONE → IDLE
    typedef enum {IDLE, LOOPING, OUTER_LOOP, INNER_LOOP, DONE} state_type;
    state_type state_nxt, state_crnt;
    
    // 各维度当前计数器
    logic [D_WIDTH - 1:0] D_nxt, D_crnt;
    logic [W_WIDTH - 1:0] W_nxt, W_crnt;
    logic [n_WIDTH - 1:0] n_nxt, n_crnt;
    logic [q_WIDTH - 1:0] q_nxt, q_crnt;
    logic [r_WIDTH - 1:0] r_nxt, r_crnt;
        
    // ---- 时序逻辑 ----
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            n_crnt <= 0;
            W_crnt <= 0;
            q_crnt <= 0;
            D_crnt <= 0;
            r_crnt <= 0;
        end else begin
            state_crnt <= state_nxt;
            n_crnt <= n_nxt;
            W_crnt <= W_nxt;
            q_crnt <= q_nxt;
            D_crnt <= D_nxt;
            r_crnt <= r_nxt;
        end
    end
    
    // ---- 组合逻辑: FSM ----
    always @(*) begin
        // 默认赋值
        busy = 1'b0;
        done = 1'b0;
        state_nxt = state_crnt;
        n_nxt = n_crnt;
        W_nxt = W_crnt;
        q_nxt = q_crnt;
        D_nxt = D_crnt;
        r_nxt = r_crnt;
        
        case(state_crnt)
            IDLE:
            begin
                if (start) begin
                    state_nxt = LOOPING;
                end 
            end
            
            // LOOPING: 单层嵌套循环
            // 嵌套结构(从内到外): r(通道复用) → D(行) → q(通道分块) → W(列) → n(批)
            // 每次await=0时步进一次, 按最内层r开始进位
            LOOPING:
            begin
               if (!await) begin          // 无反压
                    busy = 1'b1;          // 忙标志
                    if (r_crnt == r - 1) begin         // r(最内层)到头?
                        if (D_crnt == D - 1) begin     // D到头?
                            if (q_crnt == q - 1) begin // q到头?
                                if (W_crnt == W - 1) begin  // W到头?
                                    if (n_crnt == n - 1) begin  // n(最外层)也到头?
                                        // 全部完成
                                        state_nxt = DONE;
                                        n_nxt = 0;
                                        W_nxt = 0;
                                        q_nxt = 0;
                                        D_nxt = 0;
                                        r_nxt = 0;
                                    end else begin
                                        // n递增, 内层全部归零
                                        n_nxt = n_crnt + 1;
                                        W_nxt = 0;
                                        q_nxt = 0;
                                        D_nxt = 0;
                                        r_nxt = 0;
                                    end
                                end else begin
                                    // W递增, q,D,r归零
                                    W_nxt = W_crnt + 1;
                                    q_nxt = 0;
                                    D_nxt = 0;
                                    r_nxt = 0;
                                end
                            end else begin
                                // q递增, D,r归零
                                q_nxt = q_crnt + 1;
                                D_nxt = 0;
                                r_nxt = 0;
                            end
                        end else begin
                            // D递增, r归零
                            D_nxt = D_crnt + 1;
                            r_nxt = 0;
                        end
                    end else begin
                        // r递增
                        r_nxt = r_crnt + 1; 
                    end
                end
            end
            DONE:
            begin
                done = 1'b1;
                state_nxt = IDLE;
            end
            default: state_nxt = IDLE;
        endcase
    end
    
    // ---- 索引输出 ----
    // ifmap_index = n_crnt: 当前批索引
    // channel_index = q_crnt + r_crnt * q: 在q×r通道平面内的线性索引
    // row_index = D_crnt: 当前行号
    // col_index = W_crnt: 当前列号
    always @(*) begin
        ifmap_index   = n_crnt;
        channel_index = q_crnt + r_crnt * q;
        row_index     = D_crnt;
        col_index     = W_crnt;
    end
        
endmodule
