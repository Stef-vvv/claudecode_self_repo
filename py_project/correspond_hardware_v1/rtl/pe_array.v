// ===========================================================================
// PE_Array.v — 3×3 Row-Stationary PE阵列 (匹配 pe_array.py)
// ===========================================================================
// 对应Python: ed_run/pe_array.py — PEArray.process()
//
// 数据流 (简化RS):
//   Data:  广播到全部9个PE (同一总线, 对应Python: self.grid[j][i].in_data = data_port)
//   Filter: 从列0向右传播 (对应Python: self.grid[j][i].in_filter = self.grid[j][i-1].filter)
//   Psum:  从行0向下传播 (对应Python: self.grid[j][i].in_result = self.grid[j-1][i].result)
//   Start: 对角线传播 (对应Python: above_start OR left_start)
//   输出:  取最底部行第一个完成的PE结果 (对应Python: break on first finished)
//
// 关键简化: 数据广播使阵列等效3x1垂直累加器, 第0列PE产生正确结果,
//           第1,2列执行冗余计算(模拟RS运动). 这是简化RS设计的核心特征.
// ===========================================================================

`timescale 1ns / 1ps

module PE_Array #(
    parameter N         = 3,         // 阵列尺寸 (3x3)
    parameter IN_WIDTH  = 5,
    parameter W_WIDTH   = 8,
    parameter ACC_WIDTH = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start_global,    // 对应Python: grid[0][0].start[0]=1 (scheduler设置)
    input  wire                          new_in_data,     // 数据有效 (广播到全部PE)
    input  wire [ IN_WIDTH*5 -1 : 0]     in_data,         // 5数据值打包 (广播总线)
    input  wire [  W_WIDTH*3 -1 : 0]     in_filter,       // 3滤波器值打包 (仅列0)
    input  wire [ ACC_WIDTH*3 -1 : 0]    in_psum_top,     // 顶部部分和 (通常0)

    output wire [ ACC_WIDTH*3 -1 : 0]    out_result,      // 阵列输出 (底部行第0列)
    output wire                          out_finished     // 阵列完成 (任一底部PE完成)
);

    localparam ROWS = 3, COLS = 3;
    genvar r, c;

    // ---- PE互连信号网 ----
    wire [ IN_WIDTH*5 -1 : 0] data_bus   [0:ROWS-1][0:COLS-1];
    wire [  W_WIDTH*3 -1 : 0] filt_in    [0:ROWS-1][0:COLS-1];
    wire [  W_WIDTH*3 -1 : 0] filt_out   [0:ROWS-1][0:COLS-1];
    wire [ ACC_WIDTH*3 -1 : 0] psum_in    [0:ROWS-1][0:COLS-1];
    wire [ ACC_WIDTH*3 -1 : 0] psum_out   [0:ROWS-1][0:COLS-1];
    wire                       start_pe   [0:ROWS-1][0:COLS-1];
    wire                       finished_pe[0:ROWS-1][0:COLS-1];
    wire                       out_start  [0:ROWS-1][0:COLS-1];

    // ========================================================================
    // 数据广播: 全部PE共享同一in_data总线
    // 对应Python: self.grid[j][i].in_data = data_port (for all i,j)
    // ========================================================================
    generate
        for (r = 0; r < ROWS; r = r + 1) begin
            for (c = 0; c < COLS; c = c + 1) begin
                assign data_bus[r][c] = in_data;
            end
        end
    endgenerate

    // ========================================================================
    // 滤波器连接: 列0 ← 外部, 列1,2 ← 左邻PE.out_filter
    // 对应Python: if i==0: self.grid[j][i].in_filter = filter_port
    //             else:   self.grid[j][i].in_filter = self.grid[j][i-1].filter
    // ========================================================================
    generate
        for (r = 0; r < ROWS; r = r + 1) begin
            for (c = 0; c < COLS; c = c + 1) begin
                if (c == 0)
                    assign filt_in[r][c] = in_filter;
                else
                    assign filt_in[r][c] = filt_out[r][c-1];
            end
        end
    endgenerate

    // ========================================================================
    // 部分和连接: 行0 ← 外部, 行1,2 ← 上邻PE.out_result
    // 对应Python: if j!=0 and grid[j-1][i].finished:
    //                 grid[j][i].in_result = grid[j-1][i].result
    // 硬件中无需检查finished (流水线保证了上方先完成), 直接连线.
    // ========================================================================
    generate
        for (r = 0; r < ROWS; r = r + 1) begin
            for (c = 0; c < COLS; c = c + 1) begin
                if (r == 0)
                    assign psum_in[r][c] = in_psum_top;
                else
                    assign psum_in[r][c] = psum_out[r-1][c];
            end
        end
    endgenerate

    // ========================================================================
    // 启动信号传播: 对角线传播 (左out_start | 上out_start)
    // 对应Python: above_start = grid[j-1][i].out_start
    //             left_start  = grid[j][i-1].out_start
    //             grid[j][i].start = above_start or left_start
    // ========================================================================
    generate
        for (r = 0; r < ROWS; r = r + 1) begin
            for (c = 0; c < COLS; c = c + 1) begin
                if (r == 0 && c == 0)
                    assign start_pe[r][c] = start_global;
                else begin
                    wire left_s  = (c > 0) ? out_start[r][c-1] : 1'b0;
                    wire above_s = (r > 0) ? out_start[r-1][c] : 1'b0;
                    assign start_pe[r][c] = left_s | above_s;
                end
            end
        end
    endgenerate

    // ========================================================================
    // PE实例化 (generate块, 综合为9个独立PE)
    // ========================================================================
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : gen_row
            for (c = 0; c < COLS; c = c + 1) begin : gen_col
                PE #(
                    .IN_WIDTH (IN_WIDTH),
                    .W_WIDTH  (W_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH)
                ) u_pe (
                    .clk        (clk),
                    .rst_n      (rst_n),
                    .start      (start_pe[r][c]),
                    .new_in_data(new_in_data),
                    .in_data    (data_bus[r][c]),
                    .in_filter  (filt_in[r][c]),
                    .in_result  (psum_in[r][c]),
                    .out_result (psum_out[r][c]),
                    .out_filter (filt_out[r][c]),
                    .out_start  (out_start[r][c]),
                    .finished   (finished_pe[r][c])
                );
            end
        end
    endgenerate

    // ========================================================================
    // 阵列输出: 最底行第一个完成的PE结果
    // 对应Python: for i in range(n): if grid[n-1][i].finished: output=result; break
    // 简化RS中, 列0最先完成 → 取列0结果.
    // ========================================================================
    assign out_result = finished_pe[ROWS-1][0] ? psum_out[ROWS-1][0] :
                        finished_pe[ROWS-1][1] ? psum_out[ROWS-1][1] :
                        finished_pe[ROWS-1][2] ? psum_out[ROWS-1][2] :
                        {ACC_WIDTH*3{1'b0}};
    assign out_finished = finished_pe[ROWS-1][0] | finished_pe[ROWS-1][1] | finished_pe[ROWS-1][2];

endmodule
