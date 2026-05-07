// rs_top_tb.v — System-Level Testbench for RS Accelerator

`timescale 1ns / 1ps

module rs_top_tb;

    localparam IN_WIDTH  = 5;
    localparam W_WIDTH   = 8;
    localparam ACC_WIDTH = 16;
    localparam CLK_PERIOD = 10;

    reg  clk, rst_n, start_cmd;
    reg  [ IN_WIDTH*5 -1 : 0] ifmap_row0, ifmap_row1, ifmap_row2;
    reg  [  W_WIDTH*3 -1 : 0] filter_row0, filter_row1, filter_row2;
    reg  [ACC_WIDTH*3 -1 : 0] psum_top;
    reg  [ACC_WIDTH*16-1 : 0] prev_partial;

    wire [ACC_WIDTH*3 -1 : 0] acc_result;
    wire acc_valid, tile_done;

    rs_top #(
        .IN_WIDTH (IN_WIDTH),
        .W_WIDTH  (W_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) u_top (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_cmd   (start_cmd),
        .ifmap_row0  (ifmap_row0),
        .ifmap_row1  (ifmap_row1),
        .ifmap_row2  (ifmap_row2),
        .filter_row0 (filter_row0),
        .filter_row1 (filter_row1),
        .filter_row2 (filter_row2),
        .psum_top    (psum_top),
        .prev_partial(prev_partial),
        .acc_result  (acc_result),
        .acc_valid   (acc_valid),
        .tile_done   (tile_done)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    function [IN_WIDTH*5-1:0] pack_d;
        input [IN_WIDTH-1:0] d0, d1, d2, d3, d4;
        begin pack_d = {d4, d3, d2, d1, d0}; end
    endfunction

    function [W_WIDTH*3-1:0] pack_f;
        input [W_WIDTH-1:0] f0, f1, f2;
        begin pack_f = {f2, f1, f0}; end
    endfunction

    reg test_pass;

    initial begin
        rst_n = 0; start_cmd = 0;
        ifmap_row0 = 0; ifmap_row1 = 0; ifmap_row2 = 0;
        filter_row0 = 0; filter_row1 = 0; filter_row2 = 0;
        psum_top = 0; prev_partial = 0;
        test_pass = 1;

        #(CLK_PERIOD * 2);
        rst_n = 1;
        #(CLK_PERIOD);

        // ====================================
        // TEST: 3×3 conv tile [411, 456, 501]
        // ====================================
        $display("=== System Test: Full RS Dataflow ===");

        ifmap_row0  = pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        ifmap_row1  = pack_d(5'd6, 5'd7, 5'd8, 5'd9, 5'd10);
        ifmap_row2  = pack_d(5'd11, 5'd12, 5'd13, 5'd14, 5'd15);
        filter_row0 = pack_f(8'd1, 8'd2, 8'd3);
        filter_row1 = pack_f(8'd4, 8'd5, 8'd6);
        filter_row2 = pack_f(8'd7, 8'd8, 8'd9);

        start_cmd = 1;
        #(CLK_PERIOD);
        start_cmd = 0;

        // Wait for aggregator output
        wait(acc_valid == 1'b1);
        #(CLK_PERIOD * 0.3);

        $display("  acc_result = (%0d, %0d, %0d)",
            acc_result[0*ACC_WIDTH +: ACC_WIDTH],
            acc_result[1*ACC_WIDTH +: ACC_WIDTH],
            acc_result[2*ACC_WIDTH +: ACC_WIDTH]);

        if (acc_result[0*ACC_WIDTH +: ACC_WIDTH] != 16'd411 ||
            acc_result[1*ACC_WIDTH +: ACC_WIDTH] != 16'd456 ||
            acc_result[2*ACC_WIDTH +: ACC_WIDTH] != 16'd501) begin
            $display("  FAIL: expected (411, 456, 501)");
            test_pass = 0;
        end else
            $display("  PASS");

        // Wait for tile_done
        wait(tile_done == 1'b1);
        #(CLK_PERIOD);
        wait(tile_done == 1'b0);
        #(CLK_PERIOD * 3);

        // ====================================
        // Second tile: simple all-ones filter
        // ====================================
        $display("=== System Test: Simple Tile ===");

        ifmap_row0  = pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        ifmap_row1  = pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        ifmap_row2  = pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        filter_row0 = pack_f(8'd1, 8'd1, 8'd1);
        filter_row1 = pack_f(8'd1, 8'd1, 8'd1);
        filter_row2 = pack_f(8'd1, 8'd1, 8'd1);

        start_cmd = 1;
        #(CLK_PERIOD);
        start_cmd = 0;

        wait(acc_valid == 1'b1);
        #(CLK_PERIOD * 0.3);

        $display("  acc_result = (%0d, %0d, %0d)",
            acc_result[0*ACC_WIDTH +: ACC_WIDTH],
            acc_result[1*ACC_WIDTH +: ACC_WIDTH],
            acc_result[2*ACC_WIDTH +: ACC_WIDTH]);

        // Each row: dot=[6,9,12], accumulated ×3 = [18,27,36]
        if (acc_result[0*ACC_WIDTH +: ACC_WIDTH] != 16'd18 ||
            acc_result[1*ACC_WIDTH +: ACC_WIDTH] != 16'd27 ||
            acc_result[2*ACC_WIDTH +: ACC_WIDTH] != 16'd36) begin
            $display("  FAIL: expected (18, 27, 36)");
            test_pass = 0;
        end else
            $display("  PASS");

        // ====================================
        // Summary
        // ====================================
        if (test_pass)
            $display("\n=== ALL SYSTEM TESTS PASSED ===");
        else
            $display("\n=== SOME SYSTEM TESTS FAILED ===");

        #(CLK_PERIOD * 5);
        $finish;
    end

    initial begin
        $dumpfile("rs_top_tb.vcd");
        $dumpvars(0, rs_top_tb);
    end

endmodule
