// PE_Array_tb.v — Testbench for 3x3 PE Array
//
// Tests: same-data accumulation, different-data RS emulation, output timing

`timescale 1ns / 1ps

module pe_array_tb;

    localparam IN_WIDTH  = 5;
    localparam W_WIDTH   = 8;
    localparam ACC_WIDTH = 16;
    localparam CLK_PERIOD = 10;

    reg  clk;
    reg  rst_n;
    reg  start_global;
    reg  new_in_data;
    reg  [ IN_WIDTH*5 -1 : 0] in_data;
    reg  [  W_WIDTH*3 -1 : 0] in_filter;
    reg  [ACC_WIDTH*3 -1 : 0] in_psum_top;
    wire [ACC_WIDTH*3 -1 : 0] out_result;
    wire out_finished;

    PE_Array #(
        .N         (3),
        .IN_WIDTH  (IN_WIDTH),
        .W_WIDTH   (W_WIDTH),
        .ACC_WIDTH (ACC_WIDTH)
    ) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start_global (start_global),
        .new_in_data  (new_in_data),
        .in_data      (in_data),
        .in_filter    (in_filter),
        .in_psum_top  (in_psum_top),
        .out_result   (out_result),
        .out_finished (out_finished)
    );

    // ---- Clock ----
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Helpers ----
    function [IN_WIDTH*5-1:0] pack_data;
        input [IN_WIDTH-1:0] d0, d1, d2, d3, d4;
        begin pack_data = {d4, d3, d2, d1, d0}; end
    endfunction

    function [W_WIDTH*3-1:0] pack_filt;
        input [W_WIDTH-1:0] f0, f1, f2;
        begin pack_filt = {f2, f1, f0}; end
    endfunction

    function [ACC_WIDTH*3-1:0] pack_psum;
        input [ACC_WIDTH-1:0] p0, p1, p2;
        begin pack_psum = {p2, p1, p0}; end
    endfunction

    reg test_pass;
    reg [ACC_WIDTH-1:0] exp_r0, exp_r1, exp_r2;

    // ---- Test procedure ----
    initial begin
        // Init
        rst_n = 0;
        start_global = 0;
        new_in_data = 0;
        in_data = 0;
        in_filter = 0;
        in_psum_top = 0;
        test_pass = 1;

        #(CLK_PERIOD * 2);
        rst_n = 1;
        #(CLK_PERIOD);

        // ====================
        // TEST 1: Same data rows — vertical accumulation
        // ====================
        $display("=== TEST 1: Same data — vertical accumulation ===");

        in_data    = pack_data(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        in_filter  = pack_filt(8'd1, 8'd2, 8'd3);
        in_psum_top = 0;

        // Pulse start + new_in_data
        start_global = 1;
        new_in_data  = 1;
        #(CLK_PERIOD);
        start_global = 0;
        new_in_data  = 0;

        // Wait for finish
        wait(out_finished == 1'b1);
        #(1);

        // Expected: PE(2,0) = [14,20,26] × 3 = [42,60,78]
        exp_r0 = 16'd42; exp_r1 = 16'd60; exp_r2 = 16'd78;
        if (out_result[0*ACC_WIDTH +: ACC_WIDTH] != exp_r0 ||
            out_result[1*ACC_WIDTH +: ACC_WIDTH] != exp_r1 ||
            out_result[2*ACC_WIDTH +: ACC_WIDTH] != exp_r2) begin
            $display("  FAIL: result=(%0d,%0d,%0d), expected=(%0d,%0d,%0d)",
                out_result[0*ACC_WIDTH +: ACC_WIDTH],
                out_result[1*ACC_WIDTH +: ACC_WIDTH],
                out_result[2*ACC_WIDTH +: ACC_WIDTH],
                exp_r0, exp_r1, exp_r2);
            test_pass = 0;
        end else
            $display("  PASS");

        // Wait for array to go back idle
        wait(out_finished == 1'b0);
        #(CLK_PERIOD * 3);

        // ====================
        // TEST 2: Different data rows — RS emulation
        // ====================
        $display("=== TEST 2: Different data rows — RS emulation ===");

        in_psum_top = 0;

        // Cycle 0: row0 data + row0 filter
        in_data   = pack_data(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        in_filter = pack_filt(8'd1, 8'd2, 8'd3);
        start_global = 1;
        new_in_data  = 1;
        #(CLK_PERIOD);
        start_global = 0;

        // Cycle 1: row1 data + row1 filter
        in_data   = pack_data(5'd6, 5'd7, 5'd8, 5'd9, 5'd10);
        in_filter = pack_filt(8'd4, 8'd5, 8'd6);
        #(CLK_PERIOD);

        // Cycle 2: row2 data + row2 filter, clear new_in_data after
        in_data   = pack_data(5'd11, 5'd12, 5'd13, 5'd14, 5'd15);
        in_filter = pack_filt(8'd7, 8'd8, 8'd9);
        #(CLK_PERIOD);
        new_in_data = 0;

        // Wait for pipeline drain
        wait(out_finished == 1'b1);
        #(1);

        exp_r0 = 16'd411; exp_r1 = 16'd456; exp_r2 = 16'd501;
        if (out_result[0*ACC_WIDTH +: ACC_WIDTH] != exp_r0 ||
            out_result[1*ACC_WIDTH +: ACC_WIDTH] != exp_r1 ||
            out_result[2*ACC_WIDTH +: ACC_WIDTH] != exp_r2) begin
            $display("  FAIL: result=(%0d,%0d,%0d), expected=(%0d,%0d,%0d)",
                out_result[0*ACC_WIDTH +: ACC_WIDTH],
                out_result[1*ACC_WIDTH +: ACC_WIDTH],
                out_result[2*ACC_WIDTH +: ACC_WIDTH],
                exp_r0, exp_r1, exp_r2);
            test_pass = 0;
        end else
            $display("  PASS");

        wait(out_finished == 1'b0);
        #(CLK_PERIOD * 3);

        // ====================
        // TEST 3: Selective new_in_data (hardware-accurate scheduler)
        // ====================
        $display("=== TEST 3: Selective new_in_data ===");

        // Reset
        rst_n = 0;
        #(CLK_PERIOD * 2);
        rst_n = 1;
        #(CLK_PERIOD);
        in_psum_top = 0;

        // Cycle 0: only PE(0,0) should latch (it gets start=1)
        in_data   = pack_data(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        in_filter = pack_filt(8'd1, 8'd2, 8'd3);
        start_global = 1;
        new_in_data  = 1;  // PE(0,0) latches now
        #(CLK_PERIOD);
        start_global = 0;  // Subsequent starts come from out_start propagation
        // new_in_data stays 1 for PEs that will receive propagated start

        // Cycle 1: PE(0,1) & PE(1,0) get out_start from PE(0,0)
        in_data   = pack_data(5'd6, 5'd7, 5'd8, 5'd9, 5'd10);
        in_filter = pack_filt(8'd4, 8'd5, 8'd6);
        #(CLK_PERIOD);

        // Cycle 2: PE(0,2), PE(1,1), PE(2,0) get out_start
        in_data   = pack_data(5'd11, 5'd12, 5'd13, 5'd14, 5'd15);
        in_filter = pack_filt(8'd7, 8'd8, 8'd9);
        #(CLK_PERIOD);
        new_in_data = 0;

        wait(out_finished == 1'b1);
        #(1);

        exp_r0 = 16'd411; exp_r1 = 16'd456; exp_r2 = 16'd501;
        if (out_result[0*ACC_WIDTH +: ACC_WIDTH] != exp_r0 ||
            out_result[1*ACC_WIDTH +: ACC_WIDTH] != exp_r1 ||
            out_result[2*ACC_WIDTH +: ACC_WIDTH] != exp_r2) begin
            $display("  FAIL: result=(%0d,%0d,%0d), expected=(%0d,%0d,%0d)",
                out_result[0*ACC_WIDTH +: ACC_WIDTH],
                out_result[1*ACC_WIDTH +: ACC_WIDTH],
                out_result[2*ACC_WIDTH +: ACC_WIDTH],
                exp_r0, exp_r1, exp_r2);
            test_pass = 0;
        end else
            $display("  PASS");

        // ====================
        // Summary
        // ====================
        if (test_pass)
            $display("\n=== ALL TESTS PASSED ===");
        else
            $display("\n=== SOME TESTS FAILED ===");

        #(CLK_PERIOD * 3);
        $finish;
    end

    // ---- Waveform dump ----
    initial begin
        $dumpfile("pe_array_tb.vcd");
        $dumpvars(0, pe_array_tb);
    end

endmodule
