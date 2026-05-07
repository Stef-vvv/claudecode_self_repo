// Scheduler_RS.v — Simplified RS Dataflow Scheduler
//
// Controls one PE array for a single 3x3 convolution tile.
// FSM sequence:
//   IDLE → FEED0 (cycle 0: data0 + filter0, start_global, new_in_data)
//        → FEED1 (cycle 1: data1 + filter1, new_in_data)
//        → FEED2 (cycle 2: data2 + filter2, new_in_data)
//        → DRAIN (wait for array finished)
//        → DONE → IDLE

module Scheduler_RS #(
    parameter IN_WIDTH  = 5,
    parameter W_WIDTH   = 8,
    parameter ACC_WIDTH = 16
) (
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           start_cmd,   // Start a new tile

    // Data inputs (pre-loaded from BRAM, presented externally)
    input  wire [ IN_WIDTH*5 -1 : 0]      ifmap_row0,
    input  wire [ IN_WIDTH*5 -1 : 0]      ifmap_row1,
    input  wire [ IN_WIDTH*5 -1 : 0]      ifmap_row2,
    input  wire [  W_WIDTH*3 -1 : 0]      filter_row0,
    input  wire [  W_WIDTH*3 -1 : 0]      filter_row1,
    input  wire [  W_WIDTH*3 -1 : 0]      filter_row2,
    input  wire [ACC_WIDTH*3 -1 : 0]      psum_top,

    // PE Array control outputs
    output reg                            start_global,
    output reg                            new_in_data,
    output reg  [ IN_WIDTH*5 -1 : 0]      out_data,
    output reg  [  W_WIDTH*3 -1 : 0]      out_filter,
    output reg  [ACC_WIDTH*3 -1 : 0]      out_psum_top,

    // PE Array status inputs
    input  wire [ACC_WIDTH*3 -1 : 0]      array_result,
    input  wire                           array_finished,

    // Output
    output reg  [ACC_WIDTH*3 -1 : 0]      tile_result,
    output reg                            tile_done
);

    localparam IDLE   = 3'd0;
    localparam FEED0  = 3'd1;
    localparam FEED1  = 3'd2;
    localparam FEED2  = 3'd3;
    localparam DRAIN  = 3'd4;
    localparam DONE   = 3'd5;

    reg [2:0] state, nxt_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            start_global <= 1'b0;
            new_in_data  <= 1'b0;
            out_data     <= 0;
            out_filter   <= 0;
            out_psum_top <= 0;
            tile_result  <= 0;
            tile_done    <= 1'b0;
        end else begin
            state <= nxt_state;

            case (state)
                IDLE: begin
                    tile_done    <= 1'b0;
                    start_global <= 1'b0;
                    new_in_data  <= 1'b0;
                    out_psum_top <= psum_top;
                    if (start_cmd) begin
                        out_data     <= ifmap_row0;
                        out_filter   <= filter_row0;
                        start_global <= 1'b1;
                        new_in_data  <= 1'b1;
                    end
                end

                FEED0: begin
                    start_global <= 1'b0;
                    out_data     <= ifmap_row1;
                    out_filter   <= filter_row1;
                    // new_in_data stays 1
                end

                FEED1: begin
                    out_data     <= ifmap_row2;
                    out_filter   <= filter_row2;
                end

                FEED2: begin
                    new_in_data <= 1'b0;
                end

                DRAIN: begin
                    if (array_finished) begin
                        tile_result <= array_result;
                        tile_done   <= 1'b1;
                    end
                end

                DONE: begin
                    tile_done <= 1'b0;
                end
            endcase
        end
    end

    // Next-state combinational logic
    always @(*) begin
        nxt_state = state;
        case (state)
            IDLE:   if (start_cmd)              nxt_state = FEED0;
            FEED0:                              nxt_state = FEED1;
            FEED1:                              nxt_state = FEED2;
            FEED2:                              nxt_state = DRAIN;
            DRAIN:  if (array_finished)         nxt_state = DONE;
            DONE:                               nxt_state = IDLE;
        endcase
    end

endmodule
