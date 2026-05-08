// PE.v - Row-Stationary Processing Element
// Matches Python pe.py: start cycle latches data AND computes first dot product.
// 5-cycle FSM: IDLE -> MAC(iter=0~2) -> ACC -> DONE -> IDLE
// finished=1 at cycle 4 (accumulate), back to IDLE at cycle 5.

`timescale 1ns / 1ps

module PE #(
    parameter IN_WIDTH  = 5,
    parameter W_WIDTH   = 8,
    parameter ACC_WIDTH = 16
) (
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start,
    input  wire                          new_in_data,
    input  wire [ IN_WIDTH*5 -1 : 0]     in_data,
    input  wire [  W_WIDTH*3 -1 : 0]     in_filter,
    input  wire [ ACC_WIDTH*3 -1 : 0]    in_result,

    output wire [ ACC_WIDTH*3 -1 : 0]    out_result,
    output wire [  W_WIDTH*3 -1 : 0]     out_filter,
    output reg                           out_start,
    output reg                           finished
);

    localparam IDLE = 2'd0, MAC = 2'd1, ACC = 2'd2, DONE = 2'd3;

    // Internal registers
    reg [1:0] state, nxt_state;
    reg [1:0] iter,  nxt_iter;
    reg [IN_WIDTH-1:0]   data_r [0:4];
    reg [W_WIDTH-1:0]    filt_r [0:2];
    reg [ACC_WIDTH-1:0]  result_r [0:2];

    // Combinational next-state registers
    reg [IN_WIDTH-1:0]   nxt_data [0:4];
    reg [W_WIDTH-1:0]    nxt_filt [0:2];
    reg [ACC_WIDTH-1:0]  nxt_result [0:2];
    reg                  nxt_finished;
    reg                  nxt_out_start;

    // Unpack input buses
    wire [IN_WIDTH-1:0]  in_d [0:4];
    wire [W_WIDTH-1:0]   in_f [0:2];
    wire [ACC_WIDTH-1:0] in_r [0:2];

    assign in_d[0] = in_data[0*IN_WIDTH +: IN_WIDTH];
    assign in_d[1] = in_data[1*IN_WIDTH +: IN_WIDTH];
    assign in_d[2] = in_data[2*IN_WIDTH +: IN_WIDTH];
    assign in_d[3] = in_data[3*IN_WIDTH +: IN_WIDTH];
    assign in_d[4] = in_data[4*IN_WIDTH +: IN_WIDTH];

    assign in_f[0] = in_filter[0*W_WIDTH +: W_WIDTH];
    assign in_f[1] = in_filter[1*W_WIDTH +: W_WIDTH];
    assign in_f[2] = in_filter[2*W_WIDTH +: W_WIDTH];

    assign in_r[0] = in_result[0*ACC_WIDTH +: ACC_WIDTH];
    assign in_r[1] = in_result[1*ACC_WIDTH +: ACC_WIDTH];
    assign in_r[2] = in_result[2*ACC_WIDTH +: ACC_WIDTH];

    // Combinational dot product — uses data/filter that will be latched this cycle
    wire [ACC_WIDTH-1:0] dot0, dot1, dot2;
    wire [IN_WIDTH-1:0]  dot_d [0:4];
    wire [W_WIDTH-1:0]   dot_f [0:2];

    // In IDLE+start: use input port (will be latched this cycle)
    // In MAC: use register (already latched)
    assign dot_d[0] = (state == IDLE && start && new_in_data) ? in_d[0] : data_r[0];
    assign dot_d[1] = (state == IDLE && start && new_in_data) ? in_d[1] : data_r[1];
    assign dot_d[2] = (state == IDLE && start && new_in_data) ? in_d[2] : data_r[2];
    assign dot_d[3] = (state == IDLE && start && new_in_data) ? in_d[3] : data_r[3];
    assign dot_d[4] = (state == IDLE && start && new_in_data) ? in_d[4] : data_r[4];

    assign dot_f[0] = (state == IDLE && start && new_in_data) ? in_f[0] : filt_r[0];
    assign dot_f[1] = (state == IDLE && start && new_in_data) ? in_f[1] : filt_r[1];
    assign dot_f[2] = (state == IDLE && start && new_in_data) ? in_f[2] : filt_r[2];

    assign dot0 = dot_d[0]*dot_f[0] + dot_d[1]*dot_f[1] + dot_d[2]*dot_f[2];
    assign dot1 = dot_d[1]*dot_f[0] + dot_d[2]*dot_f[1] + dot_d[3]*dot_f[2];
    assign dot2 = dot_d[2]*dot_f[0] + dot_d[3]*dot_f[1] + dot_d[4]*dot_f[2];

    // Next data/filt: latch input when in IDLE+start+new_in_data
    assign nxt_data[0] = (state == IDLE && start && new_in_data) ? in_d[0] : data_r[0];
    assign nxt_data[1] = (state == IDLE && start && new_in_data) ? in_d[1] : data_r[1];
    assign nxt_data[2] = (state == IDLE && start && new_in_data) ? in_d[2] : data_r[2];
    assign nxt_data[3] = (state == IDLE && start && new_in_data) ? in_d[3] : data_r[3];
    assign nxt_data[4] = (state == IDLE && start && new_in_data) ? in_d[4] : data_r[4];

    assign nxt_filt[0] = (state == IDLE && start && new_in_data) ? in_f[0] : filt_r[0];
    assign nxt_filt[1] = (state == IDLE && start && new_in_data) ? in_f[1] : filt_r[1];
    assign nxt_filt[2] = (state == IDLE && start && new_in_data) ? in_f[2] : filt_r[2];

    // Next result: mux between dot product and accumulated sum
    assign nxt_result[0] = (state == IDLE && start)              ? dot0 :
                           (state == MAC  && iter == 2'd0)       ? dot0 :
                           (state == ACC) ? (result_r[0] + in_r[0]) : result_r[0];
    assign nxt_result[1] = (state == MAC  && iter == 2'd1)       ? dot1 :
                           (state == ACC) ? (result_r[1] + in_r[1]) : result_r[1];
    assign nxt_result[2] = (state == MAC  && iter == 2'd2)       ? dot2 :
                           (state == ACC) ? (result_r[2] + in_r[2]) : result_r[2];

    // Next state control
    always @(*) begin
        nxt_state    = state;
        nxt_iter     = iter;
        nxt_finished = 1'b0;
        nxt_out_start = 1'b0;

        case (state)
            IDLE: begin
                if (start) begin
                    nxt_state     = MAC;
                    nxt_iter      = 2'd1;  // iter=0 MAC done this cycle
                    nxt_out_start = 1'b1;
                end
            end

            MAC: begin
                case (iter)
                    2'd0: begin nxt_iter = 2'd1; nxt_out_start = 1'b1; end
                    2'd1: begin nxt_iter = 2'd2; nxt_out_start = 1'b0; end
                    2'd2: begin nxt_iter = 2'd0; nxt_state = ACC; end
                endcase
            end

            ACC: begin
                nxt_finished = 1'b1;
                nxt_state    = DONE;
            end

            DONE: begin
                nxt_state = IDLE;
                nxt_iter  = 2'd0;
            end
        endcase
    end

    // Sequential register update
    integer ri;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            iter      <= 2'd0;
            finished  <= 1'b0;
            out_start <= 1'b0;
            for (ri = 0; ri < 5; ri = ri + 1) data_r[ri]   <= 0;
            for (ri = 0; ri < 3; ri = ri + 1) filt_r[ri]   <= 0;
            for (ri = 0; ri < 3; ri = ri + 1) result_r[ri] <= 0;
        end else begin
            state     <= nxt_state;
            iter      <= nxt_iter;
            finished  <= nxt_finished;
            out_start <= nxt_out_start;
            for (ri = 0; ri < 5; ri = ri + 1) data_r[ri]   <= nxt_data[ri];
            for (ri = 0; ri < 3; ri = ri + 1) filt_r[ri]   <= nxt_filt[ri];
            for (ri = 0; ri < 3; ri = ri + 1) result_r[ri] <= nxt_result[ri];
        end
    end

    // Output assignments
    assign out_result = {result_r[2], result_r[1], result_r[0]};
    assign out_filter = {filt_r[2],   filt_r[1],   filt_r[0]};

endmodule
