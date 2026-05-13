// =============================================================================
// 模块名称: pass_controller (握手控制器)
// 功能描述: 管理外部start信号到NoC内部启动信号的握手转换。
//           接收外部start脉冲, 生成start_nocs脉冲启动NoC,
//           等待nocs_done后输出done脉冲和busy状态。
// 数据流角色: NoC的握手接口 —— 外部的单周期start脉冲转换为内部start_nocs脉冲,
//           内部nocs_done转换为外部的done脉冲。
// FSM: IDLE -> START_NOCS(发脉冲) -> PROCESSING(等待) -> DONE(输出done) -> IDLE
// =============================================================================

module pass_controller (
    input clk,
    input reset,
    input start,           // 外部启动脉冲

    output reg start_nocs, // NoC内部启动脉冲 (在START_NOCS状态持续1周期)
    input      nocs_done,  // NoC完成信号

    output reg busy,       // 忙状态 (PROCESSING状态期间为1)
    output reg done        // 完成脉冲 (DONE状态持续1周期)
);

    // FSM状态定义
    // IDLE:         等待外部start
    // START_NOCS:   发出start_nocs脉冲(单周期)
    // PROCESSING:   等待nocs_done
    // DONE:         输出done脉冲, 返回IDLE
    typedef enum {IDLE, START_NOCS, PROCESSING, DONE} state_type;
    state_type state_nxt, state_crnt;

    // ---- 时序逻辑: negedge clk触发 ----
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
        end else begin
            state_crnt <= state_nxt;
        end
    end

    // ---- 组合逻辑: FSM ----
    always @(*) begin
        // 默认赋值
        start_nocs = 1'b0;     // 脉冲信号, 默认0
        busy = 1'b0;
        done = 1'b0;
        state_nxt = state_crnt;

        case(state_crnt)
            // IDLE: 等待外部start
            IDLE:
            begin
                if (start) begin
                    state_nxt = START_NOCS;
                end
            end

            // START_NOCS: 发一个周期的start_nocs脉冲
            START_NOCS:
            begin
                start_nocs = 1'b1;     // 单周期脉冲
                state_nxt = PROCESSING;
            end

            // PROCESSING: 等待NoC完成
            PROCESSING:
            begin
                busy = 1'b1;
                if (nocs_done) begin
                    state_nxt = DONE;
                end
            end

            // DONE: 输出done脉冲, 返回IDLE
            DONE:
            begin
                done = 1'b1;           // 单周期完成脉冲
                state_nxt = IDLE;
            end
            default: state_nxt = IDLE;
        endcase
    end

endmodule
