// ===========================================================================
// PE_tb.v — PE模块测试平台 (匹配Python pe_test.py)
// 时序规范: 所有input在negedge clk设置, posedge clk采样, 避免竞争.
// ===========================================================================
`timescale 1ns / 1ps

module pe_tb;
    localparam IN_WIDTH  = 5;
    localparam W_WIDTH   = 8;
    localparam ACC_WIDTH = 16;
    localparam CLK_PERIOD = 10;

    reg  clk, rst_n;
    reg  start, new_in_data;
    reg  [ IN_WIDTH*5 -1 : 0] in_data;
    reg  [  W_WIDTH*3 -1 : 0] in_filter;
    reg  [ ACC_WIDTH*3 -1 : 0] in_result;
    wire [ ACC_WIDTH*3 -1 : 0] out_result;
    wire [  W_WIDTH*3 -1 : 0] out_filter;
    wire out_start, finished;

    PE #(.IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
        u_pe (.clk(clk), .rst_n(rst_n), .start(start), .new_in_data(new_in_data),
              .in_data(in_data), .in_filter(in_filter), .in_result(in_result),
              .out_result(out_result), .out_filter(out_filter),
              .out_start(out_start), .finished(finished));

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
    function [ACC_WIDTH*3-1:0] pack_r;
        input [ACC_WIDTH-1:0] r0, r1, r2;
        begin pack_r = {r2, r1, r0}; end
    endfunction

    integer test_pass;

    // 辅助task: 发送单次start脉冲并等待完成
    task send_start_and_wait;
        input [IN_WIDTH*5-1:0] d;
        input [W_WIDTH*3-1:0] f;
        input [ACC_WIDTH*3-1:0] r;
        input nd;  // new_in_data
        begin
            @(negedge clk);
            in_data = d; in_filter = f; in_result = r;
            start = nd ? 1 : 1;  // start always 1
            new_in_data = nd;
            @(negedge clk);
            start = 0; new_in_data = 0;
        end
    endtask

    initial begin
        rst_n = 0; start = 0; new_in_data = 0;
        in_data = 0; in_filter = 0; in_result = 0;
        test_pass = 1;
        #(CLK_PERIOD * 2);
        rst_n = 1;
        @(negedge clk);

        // ====================================
        // Test1: Basic MAC
        // Python: data=[1,2,3,4,5], filter=[1,1,1] → [6,9,12]
        // ====================================
        $display("=== TEST 1: Basic MAC ===");
        @(negedge clk);
        in_data   = pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        in_filter = pack_f(8'd1, 8'd1, 8'd1);
        in_result = 0;
        start = 1; new_in_data = 1;
        @(negedge clk);
        start = 0; new_in_data = 0;

        wait(finished == 1'b1);
        if (out_result[0*ACC_WIDTH +: ACC_WIDTH] != 16'd6 ||
            out_result[1*ACC_WIDTH +: ACC_WIDTH] != 16'd9 ||
            out_result[2*ACC_WIDTH +: ACC_WIDTH] != 16'd12) begin
            $display("  FAIL: result=(%0d,%0d,%0d) expected=(6,9,12)",
                out_result[0*ACC_WIDTH +: ACC_WIDTH],
                out_result[1*ACC_WIDTH +: ACC_WIDTH],
                out_result[2*ACC_WIDTH +: ACC_WIDTH]);
            test_pass = 0;
        end else $display("  PASS");

        wait(finished == 1'b0);

        // ====================================
        // Test2: MAC + Accumulation
        // Python: data=[0,1,2,3,4], filter=[4,3,2], psum=[10,20,30] → [17,36,55]
        // ====================================
        $display("=== TEST 2: MAC + Accumulation ===");
        @(negedge clk);
        in_data   = pack_d(5'd0, 5'd1, 5'd2, 5'd3, 5'd4);
        in_filter = pack_f(8'd4, 8'd3, 8'd2);
        in_result = pack_r(16'd10, 16'd20, 16'd30);
        start = 1; new_in_data = 1;
        @(negedge clk);
        start = 0; new_in_data = 0;

        wait(finished == 1'b1);
        if (out_result[0*ACC_WIDTH +: ACC_WIDTH] != 16'd17 ||
            out_result[1*ACC_WIDTH +: ACC_WIDTH] != 16'd36 ||
            out_result[2*ACC_WIDTH +: ACC_WIDTH] != 16'd55) begin
            $display("  FAIL: result=(%0d,%0d,%0d) expected=(17,36,55)",
                out_result[0*ACC_WIDTH +: ACC_WIDTH],
                out_result[1*ACC_WIDTH +: ACC_WIDTH],
                out_result[2*ACC_WIDTH +: ACC_WIDTH]);
            test_pass = 0;
        end else $display("  PASS");

        wait(finished == 1'b0);

        // ====================================
        // Test3: Timing
        // ====================================
        $display("=== TEST 3: Timing ===");
        @(negedge clk);
        in_data   = pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        in_filter = pack_f(8'd1, 8'd1, 8'd1);
        in_result = 0;
        start = 1; new_in_data = 1;

        @(posedge clk); #1;  // 第0拍结果
        if (out_start != 1'b1) begin $display("  FAIL: T0 out_start"); test_pass = 0; end

        @(negedge clk); start = 0; new_in_data = 0;  // 清除输入
        @(posedge clk); #1;
        if (out_start != 1'b0) begin $display("  FAIL: T1 out_start"); test_pass = 0; end

        @(posedge clk); #1;
        @(posedge clk); #1;
        if (finished != 1'b1) begin $display("  FAIL: T3 finished"); test_pass = 0; end

        @(posedge clk); #1;
        if (finished != 1'b0) begin $display("  FAIL: T4 back to IDLE"); test_pass = 0; end

        wait(finished == 1'b0);
        $display("  PASS (timing verified)");

        // ====================================
        // Test4: Data Latching (new_in_data=0)
        // Python: data stays old [1,2,3,4,5], filter updates to [2,2,2]
        //         + psum [100,100,100] = [112,118,124]
        // ====================================
        $display("=== TEST 4: Data Latching ===");
        // First op: latch [1,2,3,4,5] + [1,1,1]
        @(negedge clk);
        in_data   = pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5);
        in_filter = pack_f(8'd1, 8'd1, 8'd1);
        in_result = 0;
        start = 1; new_in_data = 1;
        @(negedge clk); start = 0; new_in_data = 0;
        wait(finished); wait(~finished);

        // Second op: new_in_data=0 — data stays old, filter updates
        @(negedge clk);
        in_data   = pack_d(5'd9, 5'd9, 5'd9, 5'd9, 5'd9);
        in_filter = pack_f(8'd2, 8'd2, 8'd2);
        in_result = pack_r(16'd100, 16'd100, 16'd100);
        start = 1; new_in_data = 0;
        @(negedge clk); start = 0;
        wait(finished);

        if (out_result[0*ACC_WIDTH +: ACC_WIDTH] != 16'd112 ||
            out_result[1*ACC_WIDTH +: ACC_WIDTH] != 16'd118 ||
            out_result[2*ACC_WIDTH +: ACC_WIDTH] != 16'd124) begin
            $display("  FAIL: result=(%0d,%0d,%0d) expected=(112,118,124)",
                out_result[0*ACC_WIDTH +: ACC_WIDTH],
                out_result[1*ACC_WIDTH +: ACC_WIDTH],
                out_result[2*ACC_WIDTH +: ACC_WIDTH]);
            test_pass = 0;
        end else $display("  PASS");

        // ====================================
        if (test_pass) $display("\n=== ALL TESTS PASSED ===");
        else $display("\n=== SOME TESTS FAILED ===");
        #(CLK_PERIOD * 3);
        $finish;
    end

endmodule
