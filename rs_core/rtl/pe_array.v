// PE_Array.v — 3x3 Row-Stationary PE Array
//
// Architecture:
//   Data:       broadcast to all 9 PEs (same in_data bus)
//   Filter:     propagates RIGHT from col-0 (externally supplied)
//   Partial sum: propagates DOWN from row-0
//   Start:      propagates DIAGONALLY (out_start from left OR above)
//   Output:     result from first-finished PE in bottom row
//
// This is a SIMPLIFIED Row Stationary array. In true RS, data is
// shared diagonally between PEs. Here it is broadcast, requiring
// the scheduler to place correct data on the bus at each cycle.

module PE_Array #(
    parameter N         = 3,
    parameter IN_WIDTH  = 5,
    parameter W_WIDTH   = 8,
    parameter ACC_WIDTH = 16
) (
    input  wire                            clk,
    input  wire                            rst_n,
    input  wire                            start_global,   // start pulse to PE(0,0)
    input  wire                            new_in_data,    // data valid broadcast to all PEs
    input  wire [ IN_WIDTH*5 -1 : 0]       in_data,       // 5 data values (broadcast)
    input  wire [  W_WIDTH*3 -1 : 0]       in_filter,     // 3 filter weights (to col-0)
    input  wire [ACC_WIDTH*3 -1 : 0]       in_psum_top,   // top partial sum (usually 0)

    output wire [ACC_WIDTH*3 -1 : 0]       out_result,    // bottom row result
    output reg                             out_finished   // array computation done
);

    localparam ROWS = 3, COLS = 3;
    genvar r, c;

    // ---- Inter-PE wiring ----
    wire [ IN_WIDTH*5 -1 : 0] data_bus   [0:ROWS-1][0:COLS-1];
    wire [  W_WIDTH*3 -1 : 0] filt_in    [0:ROWS-1][0:COLS-1];
    wire [  W_WIDTH*3 -1 : 0] filt_out   [0:ROWS-1][0:COLS-1];
    wire [ACC_WIDTH*3 -1 : 0] psum_in    [0:ROWS-1][0:COLS-1];
    wire [ACC_WIDTH*3 -1 : 0] psum_out   [0:ROWS-1][0:COLS-1];
    wire                       start_pe  [0:ROWS-1][0:COLS-1];
    wire                       finished  [0:ROWS-1][0:COLS-1];
    wire                       out_start [0:ROWS-1][0:COLS-1];

    // ---- Data broadcast: all PEs share in_data ----
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : gen_dr
            for (c = 0; c < COLS; c = c + 1) begin : gen_dc
                assign data_bus[r][c] = in_data;
            end
        end
    endgenerate

    // ---- Filter wiring: col-0 from external, rest from left PE ----
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : gen_fr
            for (c = 0; c < COLS; c = c + 1) begin : gen_fc
                assign filt_in[r][c] = (c == 0) ? in_filter : filt_out[r][c-1];
            end
        end
    endgenerate

    // ---- Partial sum wiring: row-0 from external, rest from above PE ----
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : gen_pr
            for (c = 0; c < COLS; c = c + 1) begin : gen_pc
                assign psum_in[r][c] = (r == 0) ? in_psum_top : psum_out[r-1][c];
            end
        end
    endgenerate

    // ---- Start propagation: diagonal (left_out_start | above_out_start) ----
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : gen_sr
            for (c = 0; c < COLS; c = c + 1) begin : gen_sc
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

    // ---- PE instantiation ----
    generate
        for (r = 0; r < ROWS; r = r + 1) begin : gen_per
            for (c = 0; c < COLS; c = c + 1) begin : gen_pec
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
                    .finished   (finished[r][c])
                );
            end
        end
    endgenerate

    // ---- Array output: first finished PE in bottom row ----
    assign out_result = (finished[2][0]) ? psum_out[2][0] :
                        (finished[2][1]) ? psum_out[2][1] :
                        (finished[2][2]) ? psum_out[2][2] :
                        {ACC_WIDTH*3{1'b0}};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            out_finished <= 1'b0;
        else
            out_finished <= finished[2][0] | finished[2][1] | finished[2][2];
    end

endmodule
