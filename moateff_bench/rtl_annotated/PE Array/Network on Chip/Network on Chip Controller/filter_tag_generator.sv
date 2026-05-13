// =============================================================================
// 模块名称: filter_tag_generator (滤波器标签生成器)
// 功能描述: 为每个滤波器数据生成路由标签(row_tag, col_tag), 指示该数据应发往哪个PE。
//           标签空间: col_tag = t_idx + r_idx * 2 (按(t,r)平面映射), row_tag = R_idx (行号)。
// FSM: IDLE → LOOPING(与数据读出同步步进)
// 嵌套顺序: for R for r for t (每读一个数据, 递增t→r→R)
// 与filter_index_generator解耦: 标签生成器跟踪已经发出的数据数量,
//   而索引生成器负责生成存储器地址。两者通过enable信号同频驱动。
// =============================================================================

module filter_tag_generator
#( 
    // 滤波器高度位宽
    parameter R_WIDTH = 4,
    // 输入通道组数位宽
    parameter r_WIDTH = 2,
    // 输出通道组数位宽
    parameter t_WIDTH = 3,
    // 行标签位宽
    parameter ROW_TAG_WIDTH = 4,
    // 列标签位宽
    parameter COL_TAG_WIDTH = 4
) (
    input clk,
    input reset,
    input start,
    input enable,          // 步进使能: 与数据读出信号同步
    
    // 最大维度尺寸
    input [R_WIDTH - 1:0] R,   // 滤波器高度(如3)
    input [r_WIDTH - 1:0] r,   // 输入通道组数
    input [t_WIDTH - 1:0] t,   // 输出通道组数

    output reg [ROW_TAG_WIDTH - 1:0] row_tag,   // 行标签输出
    output reg [COL_TAG_WIDTH - 1:0] col_tag    // 列标签输出
);

    // FSM: IDLE → LOOPING
    typedef enum {IDLE, LOOPING} state_type;
    state_type state_nxt, state_crnt;
    
    // 各维度当前计数器
    logic [R_WIDTH - 1:0] R_crnt, R_nxt;
    logic [r_WIDTH - 1:0] r_crnt, r_nxt;  
    logic [t_WIDTH - 1:0] t_crnt, t_nxt; 

    // ---- 时序逻辑 ----
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            R_crnt <= 0;
            r_crnt <= 0;
            t_crnt <= 0;
        end else begin
            state_crnt <= state_nxt;
            R_crnt <= R_nxt;
            r_crnt <= r_nxt;
            t_crnt <= t_nxt;
        end
    end

    // ---- 组合逻辑: FSM ----
    always @(*) begin
        // 默认赋值    
        state_nxt = state_crnt;
        R_nxt = R_crnt;
        r_nxt = r_crnt;
        t_nxt = t_crnt;
            
        case (state_crnt)
            // IDLE状态: 重置所有计数器, 等待start
            IDLE: 
            begin
                R_nxt = 0;
                r_nxt = 0;
                t_nxt = 0;
                if (start) begin
                    state_nxt = LOOPING;
                end
            end
            
            // LOOPING状态: 每次enable有效时步进一次
            // 嵌套顺序: innermost t → r → R outermost
            // 每次enable: t递增, t到头→r递增而t归零, r到头→R递增而r归零
            LOOPING: 
            begin
                if (enable) begin               // 与数据读出同步
                    if (t_crnt == t - 1) begin      // t循环到头?
                        if (r_crnt == r - 1) begin  // r循环到头?
                            if (R_crnt == R - 1) begin  // R循环到头?
                                // 所有循环完成, 归零
                                R_nxt = 0;
                                t_nxt = 0;
                                r_nxt = 0; 
                            end else begin
                                // R递增, r,t归零
                                R_nxt = R_crnt + 1;
                                t_nxt = 0;
                                r_nxt = 0; 
                            end
                        end else begin
                            // r递增, t归零
                            r_nxt = r_crnt + 1;
                            t_nxt = 0;
                        end
                    end else begin
                        // t递增
                        t_nxt = t_crnt + 1;
                    end
                end
            end 
            default: state_nxt = IDLE;  
        endcase
    end

    // ---- 标签输出 ----
    // col_tag = t_crnt + r_crnt * 2
    //   含义: 在二维(t×r)标签空间中的线性映射
    //   t_crnt: 列内偏移
    //   r_crnt * 2: 跨行偏移 (r每组占2列)
    // row_tag = R_crnt: 直接使用滤波器行号作为行标签
    always @(*) begin
         col_tag = t_crnt + r_crnt * 2;
         row_tag = R_crnt;
    end

endmodule
