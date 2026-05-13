// =============================================================================
// 模块名称: psum_tag_generator (部分和标签生成器)
// 功能描述: 为每个部分和(Psum)数据生成路由标签(row_tag, col_tag)。
//           将e*t个数据映射到PE阵列的num_of_rows行和num_of_cols列。
// 标签映射策略:
//   - num_of_rows = (e * t + 13) >> 4: 将e*t个数据按16分组, 向上取整得到行数
//   - num_of_cols = 14: 固定14列(PE阵列宽度)
//   - 如果 e < 14: 行主序填充 (row先递增, row到头col递增)
//   - 如果 e >= 14: 列主序填充 (col先递增, col到头row递增)
// 总循环次数: e * t (所有输出位置的总数)
// =============================================================================

module psum_tag_generator
#(
    // 通道组数位宽
    parameter t_WIDTH = 3,
    // 特征图高度位宽
    parameter e_WIDTH = 6,
    // 行标签位宽
    parameter ROW_TAG_WIDTH = 4,
    // 列标签位宽
    parameter COL_TAG_WIDTH = 4
) (
    input clk,
    input reset,
    input start,
    input enable,          // 步进使能
    output reg busy,

    // 最大尺寸
    input [e_WIDTH - 1:0] e,    // 特征图高度
    input [t_WIDTH - 1:0] t,    // 通道组数

    output reg [ROW_TAG_WIDTH - 1:0] row_tag,
    output reg [COL_TAG_WIDTH - 1:0] col_tag
);

    // FSM: IDLE -> LOOPING
    typedef enum {IDLE, LOOPING} state_type;
    state_type state_nxt, state_crnt;

    // 游标: 当前列和行
    logic [COL_TAG_WIDTH - 1:0] col_crnt, col_nxt;
    logic [ROW_TAG_WIDTH - 1:0] row_crnt, row_nxt;
    // 总循环计数器: 从0到e*t-1
    logic [t_WIDTH + e_WIDTH - 1 : 0] counter_crnt, counter_nxt;

    // 行数: (e * t + 13) >> 4 = ceil((e*t)/16)
    // 原因: 每个PE行(共12行)可处理16个数据, 不足一行也占用一行
    logic [t_WIDTH + e_WIDTH - 5 : 0] num_of_rows;
    // 列数: 固定14 (PE阵列宽度)
    logic [3 : 0] num_of_cols ;

    assign num_of_rows = (e * t + 13) >> 4;
    assign num_of_cols = 14;

    // ---- 时序逻辑 ----
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            col_crnt <= 0;
            row_crnt <= 0;
            counter_crnt <= 0;
        end else begin
            state_crnt <= state_nxt;
            col_crnt <= col_nxt;
            row_crnt <= row_nxt;
            counter_crnt <= counter_nxt;
        end
    end

    // ---- 组合逻辑: FSM ----
    always @(*) begin
        // 默认赋值
        busy = 1'b0;
        state_nxt = state_crnt;
        col_nxt = col_crnt;
        row_nxt = row_crnt;
        counter_nxt = counter_crnt;

        case (state_crnt)
            // IDLE: 重置
            IDLE:
            begin
                col_nxt = 0;
                row_nxt = 0;
                counter_nxt = 0;
                if (start) begin
                    state_nxt = LOOPING;
                end
            end

            // LOOPING: 按行主序或列主序迭代
            LOOPING:
            begin
                if (enable) begin
                    busy = 1'b1;
                    if (counter_crnt == ((e*t)-1)) begin
                        // 总循环完成, 全部归零
                         col_nxt = 0;
                         row_nxt = 0;
                         counter_nxt = 0;
                    end else if (e<14) begin
                        // e < 14: 行主序填充 (row优先)
                        counter_nxt = counter_crnt + 1;
                        if (row_crnt == num_of_rows - 1) begin
                            if (col_crnt == num_of_cols - 1) begin
                                 col_nxt = 0;
                                 row_nxt = 0;
                                 counter_nxt = 0;
                            end else begin
                                col_nxt = col_crnt + 1;
                                row_nxt = 0;
                            end
                        end else begin
                            row_nxt = row_crnt + 1;
                        end
                    end else begin
                        // e >= 14: 列主序填充 (col优先)
                        counter_nxt = counter_crnt + 1;
                        if (col_crnt == num_of_cols - 1) begin
                            if (row_crnt == num_of_rows - 1) begin
                                col_nxt = 0;
                                row_nxt = 0;
                                counter_nxt = 0;
                            end else begin
                                row_nxt = row_crnt + 1;
                                col_nxt = 0;
                            end
                        end else begin
                            col_nxt = col_crnt + 1;
                        end
                    end
                end
            end
            default: state_nxt = IDLE;
        endcase
    end

    // ---- 标签输出 ----
    always @(*) begin
         col_tag = col_crnt;
         row_tag = row_crnt;
    end

endmodule
