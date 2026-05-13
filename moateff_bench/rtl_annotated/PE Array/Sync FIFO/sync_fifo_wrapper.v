// =============================================================================
// 模块名称: sync_fifo_wrapper (同步FIFO包装器)
// 功能描述: 在sync_fifo基础上增加读写使能的脉冲展宽控制。
//           当读写宽度不同时, 需要多个写周期完成一次读(或反之),
//           通过sync_fifo_flag_generator将外部单周期请求展宽为多周期使能。
// 使用场景:
//   WRITE_LIMIT > 0: 写宽度 < 读宽度, 需要多次写入填充一个读取单元
//   READ_LIMIT > 0: 读宽度 < 写宽度, 写入一次可支持多次读出
//   WRITE_LIMIT=0 && READ_LIMIT=0: 等宽, 直接透传
// 架构:
//   write_enable/read_enable 由 flag_generator 展宽
//   内部 sync_fifo 使用展宽后的使能
// =============================================================================

module sync_fifo_wrapper
#(
    // 读数据宽度
    parameter R_DATA_WIDTH = 16,
    // 写数据宽度
    parameter W_DATA_WIDTH = 64,
    // FIFO深度
    parameter FIFO_DEPTH   = 256,
    // 几乎满/空阈值
    parameter ALMOST_THRESH = 2
)(
    input wire                     clk,
    input wire                     reset,
    input wire                     write_request,    // 外部写请求
    input wire                     read_request,     // 外部读请求
    input wire  [W_DATA_WIDTH-1:0] wr_data,          // 写数据

    output wire [R_DATA_WIDTH-1:0] rd_data,          // 读数据
    output wire                    full_flag,
    output wire                    empty_flag,
    output wire                    almost_full_flag,
    output wire                    almost_empty_flag
);

    // WRITE_LIMIT = $clog2(R/W): 写宽度=64, 读宽度=16 -> 64000/16000=4 -> clog2(4)=2
    // 含义: 每次写请求需要展宽2拍 (因为写=4个读单元)
    localparam WRITE_LIMIT = $clog2(R_DATA_WIDTH/W_DATA_WIDTH);
    // READ_LIMIT = $clog2(W/R): R=16, W=64 -> 这个为0(因为W>R, R/W<1取clog2无意义)
    localparam READ_LIMIT = $clog2(W_DATA_WIDTH/R_DATA_WIDTH);

    // 展宽后的写使能和读使能
    wire write_enable, read_enable;

    // ---- 内部sync_fifo (使用展宽后的使能) ----
    sync_fifo #(
        .R_DATA_WIDTH(R_DATA_WIDTH),
        .W_DATA_WIDTH(W_DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .ALMOST_THRESH(ALMOST_THRESH)
    ) fifo_inst (
        .clk(clk),
        .reset(reset),
        .write_request(write_enable),    // 展宽后的写使能
        .read_request(read_enable),      // 展宽后的读使能
        .wr_data(wr_data),
        .rd_data(rd_data),
        .full_flag(full_flag),
        .empty_flag(empty_flag),
        .almost_full_flag(almost_full_flag),
        .almost_empty_flag(almost_empty_flag)
    );

    // ---- 写使能展宽 (W < R时启用) ----
    // 当写宽度小于读宽度时, 需要多次写入填充一个读单元
    // flag_generator将单次write_request展宽为WRITE_LIMIT拍的write_enable
    generate
        if (WRITE_LIMIT > 0) begin
            sync_fifo_flag_generator #(.WIDTH(WRITE_LIMIT)) write_enable_logic (
                .clk(clk),
                .reset(reset),
                .enable(write_request),
                .flag(write_enable)
            );
        end else begin
            assign write_enable = write_request;     // 等宽或W>=R, 直接透传
        end
    endgenerate


    // ---- 读使能展宽 (R < W时启用) ----
    // 当读宽度小于写宽度时, 需要多次读出消耗一个写单元
    generate
        if (READ_LIMIT > 0) begin
            sync_fifo_flag_generator #(.WIDTH(READ_LIMIT)) read_enable_logic (
                .clk(clk),
                .reset(reset),
                .enable(read_request),
                .flag(read_enable)
            );
        end else begin
            assign read_enable = read_request;       // 等宽或R>=W, 直接透传
        end
    endgenerate

endmodule
