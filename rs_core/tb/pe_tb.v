// PE_tb.v — Testbench for PE processing element
//
// Tests: basic MAC, accumulation, timing, data latching, back-to-back ops

`timescale 1ns / 1ps

module pe_tb;

    localparam IN_WIDTH  = 5;
    localparam W_WIDTH   = 8;
    localparam ACC_WIDTH = 16;
    localparam CLK_PERIOD = 10;

    reg  clk;
    reg  rst_n;
    reg  start;
    reg  new_in_data;
    reg  [ IN_WIDTH*5 -1 : 0]  in_data;
    reg  [  W_WIDTH*3 -1 : 0]  in_filter;
    reg  [ACC_WIDTH*3 -1 : 0]  in_result;

    wire [ACC_WIDTH*3 -1 : 0]  out_result;
    wire [ W_WIDTH*3 -1 : 0]   out_filter;
    wire out_start;
    wire finished;

    PE #(
        .IN_WIDTH (IN_WIDTH),
        .W_WIDTH  (W_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_pe (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .new_in_data(new_in_data),
        .in_data    (in_data),
        .in_filter  (in_filter),
        .in_result  (in_result),
        .out_result (out_result),
        .out_filter (out_filter),
        .out_start  (out_start),
        .finished   (finished)
    );

    // ---- Helper functions ----
    function [IN_WIDTH*5-1:0] pack_data;
        input [IN_WIDTH-1:0] d0, d1, d2, d3, d4;
        begin
            pack_data = {d4, d3, d2, d1, d0};
        end
    endfunction

    function [W_WIDTH*3-1:0] pack_filter;
        input [W_WIDTH-1:0] f0, f1, f2;
        begin
            pack_filter = {f2, f1, f0};
        end
    endfunction

    function [ACC_WIDTH*3-1:0] pack_result;
        input [ACC_WIDTH-1:0] r0, r1, r2;
        begin
            pack_result = {r2, r1, r0};
        end
    endfunction

    // ---- Clock ----
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- Test variables ----
    integer test_num;
    integer cycle;
    reg [ACC_WIDTH-1:0] exp_r0, exp_r1, exp_r2;
    reg test_pass;

    // ---- Test procedure ----
    initial begin
        // Reset
        rst_n = 0;
        start = 0;
        new_in_data = 0;
        in_data = 0;
        in_filter = 0;
        in_result = 0;
        test_pass = 1;

        #(CLK_PERIOD * 2);
        rst_n = 1;
        #(CLK_PERIOD);

        // ====================
        // TEST 1: Basic MAC
        // ====================
        test_num = 1;
        $display("=== TEST %0d: Basic MAC ===", test_num);

        // data=[1,2,3,4,5], filter=[1,1,1], result_in=[0,0,0]
        in_data   = pack_data(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        in_filter = pack_filter(8'd1, 8'd1, 8'd1);
        in_result = pack_result(16'd0, 16'd0, 16'd0);
        start = 1;
        new_in_data = 1;
        #(CLK_PERIOD);
        start = 0;
        new_in_data = 0;

        // Wait for finished
        wait(finished == 1'b1);
        #(CLK_PERIOD * 0.3);

        exp_r0 = 16'd6;  // 1*1+2*1+3*1
        exp_r1 = 16'd9;  // 2*1+3*1+4*1
        exp_r2 = 16'd12; // 3*1+4*1+5*1
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

        // Wait back to IDLE
        wait(finished == 1'b0);
        #(CLK_PERIOD);

        // ====================
        // TEST 2: MAC + Accumulation
        // ====================
        test_num = 2;
        $display("=== TEST %0d: MAC + Accumulation ===", test_num);

        // data=[0,1,2,3,4], filter=[4,3,2], result_in=[10,20,30]
        in_data   = pack_data(5'd0, 5'd1, 5'd2, 5'd3, 5'd4);
        in_filter = pack_filter(8'd4, 8'd3, 8'd2);
        in_result = pack_result(16'd10, 16'd20, 16'd30);
        start = 1;
        new_in_data = 1;
        #(CLK_PERIOD);
        start = 0;
        new_in_data = 0;

        wait(finished == 1'b1);
        #(CLK_PERIOD * 0.3);

        // dot=[7,16,25], result=[7+10,16+20,25+30]=[17,36,55]
        exp_r0 = 16'd17; exp_r1 = 16'd36; exp_r2 = 16'd55;
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

        wait(finished == 1'b0);
        #(CLK_PERIOD * 2);

        // ====================
        // TEST 3: Timing Check
        // ====================
        test_num = 3;
        $display("=== TEST %0d: Timing / State Transitions ===", test_num);

        in_data   = pack_data(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        in_filter = pack_filter(8'd1, 8'd1, 8'd1);
        in_result = pack_result(16'd0, 16'd0, 16'd0);
        start = 1;
        new_in_data = 1;

        // Cycle 0: start → out_start=1
        @(posedge clk);
        start = 0;
        new_in_data = 0;
        #(1);
        if (out_start != 1'b1) begin
            $display("  FAIL: Cycle 0 — out_start should be 1, got %b", out_start);
            test_pass = 0;
        end

        // Cycle 1: out_start should go to 0
        @(posedge clk);
        #(1);
        if (out_start != 1'b0) begin
            $display("  FAIL: Cycle 1 — out_start should be 0, got %b", out_start);
            test_pass = 0;
        end

        // Cycle 2: state -> ACC
        @(posedge clk);
        #(1);
        if (finished != 1'b0) begin
            $display("  FAIL: Cycle 2 — finished should still be 0");
            test_pass = 0;
        end

        // Cycle 3: finished = 1
        @(posedge clk);
        #(1);
        if (finished != 1'b1) begin
            $display("  FAIL: Cycle 3 — finished should be 1");
            test_pass = 0;
        end

        // Cycle 4: back to IDLE
        @(posedge clk);
        #(1);
        if (finished != 1'b0) begin
            $display("  FAIL: Cycle 4 — finished should be 0 (back to IDLE)");
            test_pass = 0;
        end

        $display("  %s", test_pass ? "PASS" : "FAIL (partial)");

        // ====================
        // TEST 4: Data Latching
        // ====================
        test_num = 4;
        $display("=== TEST %0d: Data Latching ===", test_num);

        // First op: latch data=[1,2,3,4,5], filter=[1,1,1]
        in_data   = pack_data(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        in_filter = pack_filter(8'd1, 8'd1, 8'd1);
        in_result = 0;
        start = 1;
        new_in_data = 1;
        @(posedge clk);
        start = 0;
        new_in_data = 0;
        wait(finished);
        wait(~finished);

        // Second op: start WITHOUT new_in_data, data should NOT update
        in_data   = pack_data(5'd9, 5'd9, 5'd9, 5'd9, 5'd9);
        in_filter = pack_filter(8'd2, 8'd2, 8'd2);
        in_result = pack_result(16'd100, 16'd100, 16'd100);
        start = 1;
        new_in_data = 0;  // no data update!
        @(posedge clk);
        start = 0;
        wait(finished);
        #(1);

        // Should use OLD data [1,1,1] and OLD filter [1,1,1] + accumulate [100,100,100]
        // result = [6+100, 9+100, 12+100] = [106, 109, 112]
        exp_r0 = 16'd106; exp_r1 = 16'd109; exp_r2 = 16'd112;
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

        wait(finished == 1'b0);
        #(CLK_PERIOD * 2);

        // ====================
        // TEST 5: Back-to-Back
        // ====================
        test_num = 5;
        $display("=== TEST %0d: Back-to-Back Operations ===", test_num);

        // Op A
        in_data   = pack_data(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        in_filter = pack_filter(8'd1, 8'd1, 8'd1);
        in_result = 0;
        start = 1; new_in_data = 1;
        @(posedge clk); start = 0; new_in_data = 0;
        wait(finished); wait(~finished);

        if (out_result[0*ACC_WIDTH +: ACC_WIDTH] != 16'd6) begin
            $display("  FAIL: Op A — result[0]=%0d, expected 6", out_result[0*ACC_WIDTH +: ACC_WIDTH]);
            test_pass = 0;
        end

        // Op B
        in_data   = pack_data(5'd2, 5'd3, 5'd4, 5'd5, 5'd6);
        in_filter = pack_filter(8'd2, 8'd2, 8'd2);
        in_result = 0;
        start = 1; new_in_data = 1;
        @(posedge clk); start = 0; new_in_data = 0;
        wait(finished); wait(~finished);

        if (out_result[0*ACC_WIDTH +: ACC_WIDTH] != 16'd18) begin
            $display("  FAIL: Op B — result[0]=%0d, expected 18", out_result[0*ACC_WIDTH +: ACC_WIDTH]);
            test_pass = 0;
        end

        // Op C
        in_data   = pack_data(5'd0, 5'd1, 5'd2, 5'd3, 5'd4);
        in_filter = pack_filter(8'd1, 8'd2, 8'd3);
        in_result = 0;
        start = 1; new_in_data = 1;
        @(posedge clk); start = 0; new_in_data = 0;
        wait(finished); wait(~finished);

        if (out_result[0*ACC_WIDTH +: ACC_WIDTH] != 16'd8) begin
            $display("  FAIL: Op C — result[0]=%0d, expected 8", out_result[0*ACC_WIDTH +: ACC_WIDTH]);
            test_pass = 0;
        end

        $display("  %s", test_pass ? "PASS" : "FAIL (partial)");

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

    // ---- Dump waveforms ----
    initial begin
        $dumpfile("pe_tb.vcd");
        $dumpvars(0, pe_tb);
    end

endmodule
