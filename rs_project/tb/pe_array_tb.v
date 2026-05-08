// ===========================================================================
// PE_Array_tb.v — PE Array 3x3 测试平台
// ===========================================================================
`timescale 1ns / 1ps

module pe_array_tb;
    localparam IN_WIDTH  = 5;
    localparam W_WIDTH   = 8;
    localparam ACC_WIDTH = 16;
    localparam CLK_PERIOD = 10;

    reg  clk, rst_n, start_global, new_in_data;
    reg  [ IN_WIDTH*5 -1 : 0] in_data;
    reg  [  W_WIDTH*3 -1 : 0] in_filter;
    reg  [ ACC_WIDTH*3 -1 : 0] in_psum_top;
    wire [ ACC_WIDTH*3 -1 : 0] out_result;
    wire out_finished;

    PE_Array #(.N(3), .IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
        u_dut (.clk(clk), .rst_n(rst_n), .start_global(start_global),
               .new_in_data(new_in_data), .in_data(in_data), .in_filter(in_filter),
               .in_psum_top(in_psum_top), .out_result(out_result), .out_finished(out_finished));

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

    // task: 安全复位 (异步复位, 同步释放)
    task do_reset;
        begin
            rst_n = 0; start_global = 0; new_in_data = 0;
            repeat(3) @(posedge clk);       // 保持3个周期复位
            @(negedge clk); rst_n = 1;       // 在negedge释放, 确保posedge前稳定
            @(negedge clk);                   // 多等半拍
        end
    endtask

    reg test_pass;

    initial begin
        in_data = 0; in_filter = 0; in_psum_top = 0;
        test_pass = 1;
        do_reset;

        // ====================================
        // Test1: 相同数据 — 单拍start+数据, new_in_data保持3拍
        // ====================================
        $display("=== TEST 1: Same Data — Vertical Accumulation ===");
        @(negedge clk);
        in_data   = pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        in_filter = pack_f(8'd1, 8'd2, 8'd3);
        in_psum_top = 0;
        start_global = 1; new_in_data = 1;
        @(negedge clk); start_global = 0;  // T1: new_in_data保持1
        @(negedge clk);                     // T2: new_in_data保持1
        @(negedge clk); new_in_data = 0;    // T3: 清除

        wait(out_finished == 1'b1);
        if (out_result[0*ACC_WIDTH +: ACC_WIDTH] != 16'd42 ||
            out_result[1*ACC_WIDTH +: ACC_WIDTH] != 16'd60 ||
            out_result[2*ACC_WIDTH +: ACC_WIDTH] != 16'd78) begin
            $display("  FAIL: result=(%0d,%0d,%0d) expected=(42,60,78)",
                out_result[0*ACC_WIDTH +: ACC_WIDTH],
                out_result[1*ACC_WIDTH +: ACC_WIDTH],
                out_result[2*ACC_WIDTH +: ACC_WIDTH]);
            test_pass = 0;
        end else $display("  PASS");

        // ====================================
        // Test2: RS数据流 — 复位后重新开始
        // ====================================
        $display("=== TEST 2: RS Dataflow ===");
        do_reset;

        // T0
        @(negedge clk);
        in_data   = pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        in_filter = pack_f(8'd1, 8'd2, 8'd3);
        in_psum_top = 0;
        start_global = 1; new_in_data = 1;

        // T1
        @(negedge clk);
        start_global = 0;
        in_data   = pack_d(5'd6, 5'd7, 5'd8, 5'd9, 5'd10);
        in_filter = pack_f(8'd4, 8'd5, 8'd6);

        // T2
        @(negedge clk);
        in_data   = pack_d(5'd11, 5'd12, 5'd13, 5'd14, 5'd15);
        in_filter = pack_f(8'd7, 8'd8, 8'd9);

        // T3: 停止
        @(negedge clk);
        new_in_data = 0;

        wait(out_finished == 1'b1);
        if (out_result[0*ACC_WIDTH +: ACC_WIDTH] != 16'd411 ||
            out_result[1*ACC_WIDTH +: ACC_WIDTH] != 16'd456 ||
            out_result[2*ACC_WIDTH +: ACC_WIDTH] != 16'd501) begin
            $display("  FAIL: result=(%0d,%0d,%0d) expected=(411,456,501)",
                out_result[0*ACC_WIDTH +: ACC_WIDTH],
                out_result[1*ACC_WIDTH +: ACC_WIDTH],
                out_result[2*ACC_WIDTH +: ACC_WIDTH]);
            test_pass = 0;
        end else $display("  PASS");

        if (test_pass) $display("\n=== ALL TESTS PASSED ===");
        else $display("\n=== SOME TESTS FAILED ===");
        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule
