// =============================================================================
// 模块名称: ifmap_tag_generator (输入特征图标签生成器)
// 功能描述: 为每个Ifmap数据生成路由标签(row_tag, col_tag), 指示该数据应发往哪个PE。
//           标签公式:
//           - col_tag = col_crnt (列游走)
//           - row_tag = U_crnt + (r_crnt * 4) (行映射: 步长偏移 + 通道组*4)
//           - max_col_id = D >> (U >> 1): 最大列标签, 由ifmap高度和步长决定
// FSM: IDLE -> LOOPING
// 嵌套: 每次enable步进, 按D->r->U->col顺序进位
// =============================================================================

module ifmap_tag_generator
#(
    // Ifmap高度位宽
    parameter D_WIDTH = 8,
    // 步长位宽
    parameter U_WIDTH = 3,
    // 通道组数位宽
    parameter r_WIDTH = 2,
    // 行标签位宽
    parameter ROW_TAG_WIDTH = 4,
    // 列标签位宽 (ifmap比filter宽1位, 因为ifmap尺寸更大)
    parameter COL_TAG_WIDTH = 5
) (
    input clk,
    input reset,
    input start,
    input enable,          // 步进使能: 与数据读出同步

    // 最大维度尺寸
    input [D_WIDTH - 1:0] D,    // Ifmap高度
    input [U_WIDTH - 1:0] U,    // 步长
    input [r_WIDTH - 1:0] r,    // 通道组数

    output reg [ROW_TAG_WIDTH - 1:0] row_tag,
    output reg [COL_TAG_WIDTH - 1:0] col_tag
);

    // FSM: IDLE -> LOOPING
    typedef enum {IDLE, LOOPING} state_type;
    state_type state_nxt, state_crnt;

    // 最大列ID: D >> (U >> 1)
    // 由ifmap高度D和步长U决定列标签的上限
    logic [COL_TAG_WIDTH - 1:0] max_col_id;
    assign max_col_id = D >> (U >> 1);

    // 各维度当前计数器
    logic [D_WIDTH - 1:0] D_crnt, D_nxt;
    logic [U_WIDTH - 1:0] U_crnt, U_nxt;
    logic [r_WIDTH - 1:0] r_crnt, r_nxt;
    logic [COL_TAG_WIDTH - 1:0] col_crnt, col_nxt;

    // ---- 时序逻辑 ----
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            r_crnt <= 0;
            D_crnt <= 0;
            U_crnt <= 0;
            col_crnt <= 0;
        end else begin
            state_crnt <= state_nxt;
            r_crnt <= r_nxt;
            D_crnt <= D_nxt;
            U_crnt <= U_nxt;
            col_crnt <= col_nxt;
        end
    end

    // ---- 组合逻辑: FSM ----
    always @(*) begin
        // 默认赋值
        state_nxt = state_crnt;
        r_nxt = r_crnt;
        D_nxt = D_crnt;
        U_nxt = U_crnt;
        col_nxt = col_crnt;

        case (state_crnt)
            // IDLE: 重置所有计数器
            IDLE:
            begin
                col_nxt = 0;
                U_nxt = 0;
                r_nxt = 0;
                D_nxt = 0;

                if (start) begin
                    state_nxt = LOOPING;
                end
            end

            // LOOPING: 每次enable步进
            // 嵌套顺序: 最内层D -> r -> U -> col (最外层)
            LOOPING:
            begin
                if (enable) begin
                    // 总计数: r * D (通道组数 * 高度)
                    if (D_crnt == (r * D) - 1) begin
                        // 所有D在r组中都遍历完, 归零
                        col_nxt = 0;
                        U_nxt = 0;
                        r_nxt = 0;
                        D_nxt = 0;
                    end else begin
                        D_nxt = D_crnt + 1;
                        if (r_crnt == r - 1) begin         // r到头
                            if (U_crnt == U - 1) begin     // U到头
                                if (col_crnt == max_col_id) begin  // col到头
                                    col_nxt = 0;
                                    U_nxt = 0;
                                    r_nxt = 0;
                                end else begin
                                    col_nxt = col_crnt + 1;
                                    U_nxt = 0;
                                    r_nxt = 0;
                                end
                            end else begin
                                U_nxt = U_crnt + 1;
                                r_nxt = 0;
                            end
                        end else begin
                            r_nxt = r_crnt + 1;
                        end
                    end
                end
            end
            default: state_nxt = IDLE;
        endcase
    end

    // ---- 标签输出 ----
    // col_tag = col_crnt: 直接使用列游走值
    // row_tag = U_crnt + (r_crnt * 4): 行标签 = 步长偏移 + 通道组*4
    always @(*) begin
        col_tag = col_crnt;
        row_tag = U_crnt + (r_crnt * 4);
    end

endmodule
