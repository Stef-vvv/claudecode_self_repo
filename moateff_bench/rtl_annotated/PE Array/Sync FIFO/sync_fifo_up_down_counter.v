// =============================================================================
// 模块名称: sync_fifo_up_down_counter (同步FIFO上升/下降计数器)
// 功能描述: 跟踪FIFO中有效数据的数量(count)。
//           写使能(inc)时 count += INC_STEP,
//           读请求(dec)时 count -= DEC_STEP,
//           同时inc和dec时 count += INC_STEP - DEC_STEP。
// 用于sync_fifo中计算almost_full和almost_empty标志。
// 步长由宽度比决定:
//   W>R: 写1产生W/R个读单元, INC_STEP=W/R, DEC_STEP=1
//   W<R: R/W个写填1个读单元, INC_STEP=1, DEC_STEP=R/W
//   W=R: INC_STEP=1, DEC_STEP=1
// =============================================================================

module sync_fifo_up_down_counter #(
    // 计数器位宽 (= ADDR_WIDTH + 1)
    parameter WIDTH    = 4,
    // 递增步长 (写使能时的增量)
    parameter INC_STEP = 1,
    // 递减步长 (读请求时的减量)
    parameter DEC_STEP = 1
)(
    input  wire clk,
    input  wire reset,

    input  wire inc,               // 写使能 (递增信号)
    input  wire dec,               // 读请求 (递减信号)
    output reg  [WIDTH-1:0] count  // 有效数据计数
);

    // ---- 时序逻辑: negedge clk触发 ----
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            count <= 0;
        end else begin
            case ({inc, dec})
                2'b00: count <= count;                      // 无操作
                2'b10: count <= count + INC_STEP;           // 只写: 递增
                2'b01: count <= count - DEC_STEP;           // 只读: 递减
                2'b11: count <= count + INC_STEP - DEC_STEP; // 同时读写: 净增减
            endcase
        end
    end

endmodule
