// PE.v — Row-Stationary Processing Element
//
// Circuit: State machine (IDLE→MAC×3→ACC→DONE→IDLE) with sliding-window MAC.
// Data and filter are latched when (start && new_in_data). The dot product
// unit uses a 3-element sliding window over 5 data values × 3 filter weights.
//
// Parameters: IN_WIDTH=5, W_WIDTH=8, ACC_WIDTH=16
// Latency: 4 cycles from start to finished, 5 cycles back to IDLE.

module PE #(
    parameter IN_WIDTH  = 5,
    parameter W_WIDTH   = 8,
    parameter ACC_WIDTH = 16
) (
    input  wire                         clk,
    input  wire                         rst_n,       // active-low reset
    input  wire                         start,        // start strobe (1 cycle)
    input  wire                         new_in_data,  // data valid / latch enable
    input  wire [  IN_WIDTH*5 -1 : 0]   in_data,     // 5 data elements packed
    input  wire [   W_WIDTH*3 -1 : 0]   in_filter,   // 3 filter weights packed
    input  wire [ ACC_WIDTH*3 -1 : 0]   in_result,   // 3 partial sums packed

    output wire [ ACC_WIDTH*3 -1 : 0]   out_result,  // 3 results packed
    output wire [  W_WIDTH*3 -1 : 0]    out_filter,  // filter passthrough
    output reg                          out_start,   // start cascade
    output reg                          finished     // computation done
);

    localparam IDLE = 2'd0, MAC = 2'd1, ACC = 2'd2, DONE = 2'd3;

    // ---- Internal registers ----
    reg [1:0] state, nxt_state;
    reg [1:0] iter,  nxt_iter;
    reg [IN_WIDTH-1:0]   data [0:4];
    reg [W_WIDTH-1:0]    filt [0:2];
    reg [ACC_WIDTH-1:0]  result [0:2];

    // ---- Unpack input buses (combinational wires) ----
    wire [IN_WIDTH-1:0]  in_d [0:4];
    wire [W_WIDTH-1:0]   in_f [0:2];
    wire [ACC_WIDTH-1:0] in_r [0:2];

    generate
        genvar gi;
        for (gi = 0; gi < 5; gi = gi + 1)
            assign in_d[gi] = in_data[gi*IN_WIDTH +: IN_WIDTH];
        for (gi = 0; gi < 3; gi = gi + 1) begin
            assign in_f[gi] = in_filter[gi*W_WIDTH +: W_WIDTH];
            assign in_r[gi] = in_result[gi*ACC_WIDTH +: ACC_WIDTH];
        end
    endgenerate

    // ---- Combinational: dot product (muxed by iter) ----
    function [ACC_WIDTH-1:0] dot;
        input integer offset;
        input [IN_WIDTH-1:0] dd [0:4];
        input [W_WIDTH-1:0]  ff [0:2];
        begin
            dot = dd[offset+0]*ff[0] + dd[offset+1]*ff[1] + dd[offset+2]*ff[2];
        end
    endfunction

    // ---- Combinational: next-state logic ----
    wire [IN_WIDTH-1:0]  nxt_data [0:4];
    wire [W_WIDTH-1:0]   nxt_filt [0:2];
    wire [ACC_WIDTH-1:0] nxt_result [0:2];
    reg  nxt_finished;
    reg  nxt_out_start;

    // Determine data source for dot product: input port (IDLE+start) or register (MAC)
    wire [IN_WIDTH-1:0] dot_data [0:4];
    wire [W_WIDTH-1:0]  dot_filt [0:2];

    generate
        for (gi = 0; gi < 5; gi = gi + 1)
            assign dot_data[gi] = (state == IDLE && start) ?
                (new_in_data ? in_d[gi] : data[gi]) : data[gi];
        for (gi = 0; gi < 3; gi = gi + 1)
            assign dot_filt[gi] = (state == IDLE && start) ?
                (new_in_data ? in_f[gi] : filt[gi]) : filt[gi];
        for (gi = 0; gi < 5; gi = gi + 1)
            assign nxt_data[gi] = (state == IDLE && start && new_in_data) ?
                in_d[gi] : data[gi];
        for (gi = 0; gi < 3; gi = gi + 1)
            assign nxt_filt[gi] = (state == IDLE && start && new_in_data) ?
                in_f[gi] : filt[gi];
    endgenerate

    wire [ACC_WIDTH-1:0] dot_result;
    assign dot_result = (iter == 0) ? dot(0, dot_data, dot_filt) :
                        (iter == 1) ? dot(1, dot_data, dot_filt) :
                        (iter == 2) ? dot(2, dot_data, dot_filt) :
                        {ACC_WIDTH{1'b0}};

    // Next-state for result: mux between dot product and accumulated sum
    generate
        for (gi = 0; gi < 3; gi = gi + 1) begin : gen_nxt_res
            assign nxt_result[gi] =
                (state == IDLE && start && gi == 0) ? dot_result :        // first MAC
                (state == MAC && iter == 1 && gi == 1) ? dot_result :    // second MAC
                (state == MAC && iter == 2 && gi == 2) ? dot_result :    // third MAC
                (state == ACC) ? (result[gi] + in_r[gi]) :                // accumulate
                result[gi];                                                // hold
        end
    endgenerate

    // Next-state control signals
    always @(*) begin
        nxt_state    = state;
        nxt_iter     = iter;
        nxt_finished = 1'b0;
        nxt_out_start = 1'b0;

        case (state)
            IDLE: begin
                if (start) begin
                    nxt_state     = MAC;
                    nxt_iter      = 2'd1;  // advance past iter0 (dot0 done)
                    nxt_out_start = 1'b1;
                end
            end

            MAC: begin
                case (iter)
                    2'd0: begin
                        nxt_iter      = 2'd1;
                        nxt_out_start = 1'b1;
                    end
                    2'd1: begin
                        nxt_iter = 2'd2;
                    end
                    2'd2: begin
                        nxt_iter  = 2'd0;
                        nxt_state = ACC;
                    end
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

    // ---- Sequential logic (register update) ----
    integer ri;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            iter      <= 2'd0;
            finished  <= 1'b0;
            out_start <= 1'b0;
            for (ri = 0; ri < 5; ri = ri + 1) data[ri]   <= {IN_WIDTH{1'b0}};
            for (ri = 0; ri < 3; ri = ri + 1) filt[ri]   <= {W_WIDTH{1'b0}};
            for (ri = 0; ri < 3; ri = ri + 1) result[ri] <= {ACC_WIDTH{1'b0}};
        end else begin
            state     <= nxt_state;
            iter      <= nxt_iter;
            finished  <= nxt_finished;
            out_start <= nxt_out_start;
            for (ri = 0; ri < 5; ri = ri + 1) data[ri]   <= nxt_data[ri];
            for (ri = 0; ri < 3; ri = ri + 1) filt[ri]   <= nxt_filt[ri];
            for (ri = 0; ri < 3; ri = ri + 1) result[ri] <= nxt_result[ri];
        end
    end

    // ---- Output assignments ----
    generate
        for (gi = 0; gi < 3; gi = gi + 1) begin
            assign out_result[gi*ACC_WIDTH +: ACC_WIDTH] = result[gi];
            assign out_filter[gi*W_WIDTH +: W_WIDTH]     = filt[gi];
        end
    endgenerate

endmodule
