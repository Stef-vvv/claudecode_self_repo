// rs_top.v — Top-Level Row Stationary Accelerator
//
// Integrates: Scheduler_RS → PE_Array → Aggregator
// Processes one 3×3 convolution tile per start_cmd pulse.

module rs_top #(
    parameter IN_WIDTH  = 5,
    parameter W_WIDTH   = 8,
    parameter ACC_WIDTH = 16
) (
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           start_cmd,

    // Data inputs
    input  wire [ IN_WIDTH*5 -1 : 0]      ifmap_row0,
    input  wire [ IN_WIDTH*5 -1 : 0]      ifmap_row1,
    input  wire [ IN_WIDTH*5 -1 : 0]      ifmap_row2,
    input  wire [  W_WIDTH*3 -1 : 0]      filter_row0,
    input  wire [  W_WIDTH*3 -1 : 0]      filter_row1,
    input  wire [  W_WIDTH*3 -1 : 0]      filter_row2,
    input  wire [ACC_WIDTH*3 -1 : 0]      psum_top,
    input  wire [ACC_WIDTH*16-1 : 0]      prev_partial,

    // Outputs
    output wire [ACC_WIDTH*3 -1 : 0]       acc_result,
    output reg                             acc_valid,
    output wire                            tile_done
);

    // Interconnect wires
    wire                        sched_start;
    wire                        sched_new_in_data;
    wire [ IN_WIDTH*5 -1 : 0]   sched_data;
    wire [  W_WIDTH*3 -1 : 0]   sched_filter;
    wire [ACC_WIDTH*3 -1 : 0]   sched_psum;
    wire [ACC_WIDTH*3 -1 : 0]   array_result;
    wire                        array_finished;

    // Scheduler
    Scheduler_RS #(
        .IN_WIDTH (IN_WIDTH),
        .W_WIDTH  (W_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_scheduler (
        .clk           (clk),
        .rst_n         (rst_n),
        .start_cmd     (start_cmd),
        .ifmap_row0    (ifmap_row0),
        .ifmap_row1    (ifmap_row1),
        .ifmap_row2    (ifmap_row2),
        .filter_row0   (filter_row0),
        .filter_row1   (filter_row1),
        .filter_row2   (filter_row2),
        .psum_top      (psum_top),
        .start_global  (sched_start),
        .new_in_data   (sched_new_in_data),
        .out_data      (sched_data),
        .out_filter    (sched_filter),
        .out_psum_top  (sched_psum),
        .array_result  (array_result),
        .array_finished(array_finished),
        .tile_result   (),
        .tile_done     (tile_done)
    );

    // PE Array
    PE_Array #(
        .N         (3),
        .IN_WIDTH  (IN_WIDTH),
        .W_WIDTH   (W_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) u_pe_array (
        .clk          (clk),
        .rst_n        (rst_n),
        .start_global (sched_start),
        .new_in_data  (sched_new_in_data),
        .in_data      (sched_data),
        .in_filter    (sched_filter),
        .in_psum_top  (sched_psum),
        .out_result   (array_result),
        .out_finished (array_finished)
    );

    // Aggregator
    Aggregator #(
        .ACC_WIDTH (ACC_WIDTH),
        .N_ARRAYS  (1),
        .OUT_WIDTH (16)
    ) u_aggregator (
        .clk            (clk),
        .rst_n          (rst_n),
        .array_result   (array_result),
        .array_finished (array_finished),
        .prev_partial   (prev_partial),
        .out_data       (acc_result),
        .out_valid      (acc_valid)
    );

    // acc_valid registered from aggregator out_valid in Aggregator module
    always @(posedge clk or negedge rst_n) begin
        // acc_valid is handled by aggregator, just re-register for timing
    end

endmodule
