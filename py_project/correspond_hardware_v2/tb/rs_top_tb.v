// ===========================================================================
// rs_top_tb.v — RS加速器系统测试平台
// ===========================================================================
// 测试: Scheduler + PE_Array + Aggregator 端到端tile处理
//
// Test1: 手算验证tile — ifmap_row[0:2]=[1..15], filter=[1,2,3]/[4,5,6]/[7,8,9]
//        期望: [411,456,501]
// Test2: 背靠背tile — 不同数据连续处理
// ===========================================================================

`timescale 1ns / 1ps

module rs_top_tb;

    localparam IN_WIDTH  = 5;
    localparam W_WIDTH   = 8;
    localparam ACC_WIDTH = 16;
    localparam CLK_PERIOD = 10;

    reg  clk, rst_n, start_tile;
    reg  [ IN_WIDTH*5 -1 : 0] ifmap_row0, ifmap_row1, ifmap_row2;
    reg  [  W_WIDTH*3 -1 : 0] filter_row0, filter_row1, filter_row2;
    reg  [ ACC_WIDTH*3 -1 : 0] psum_top, prev_partial;
    wire [ ACC_WIDTH*3 -1 : 0] acc_result;
    wire acc_valid, tile_done;

    rs_top #(.IN_WIDTH(IN_WIDTH), .W_WIDTH(W_WIDTH), .ACC_WIDTH(ACC_WIDTH))
        u_top (.clk(clk), .rst_n(rst_n), .start_tile(start_tile),
               .ifmap_row0(ifmap_row0), .ifmap_row1(ifmap_row1), .ifmap_row2(ifmap_row2),
               .filter_row0(filter_row0), .filter_row1(filter_row1), .filter_row2(filter_row2),
               .psum_top(psum_top), .prev_partial(prev_partial),
               .acc_result(acc_result), .acc_valid(acc_valid), .tile_done(tile_done));

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---- 打包函数 ----
    function [IN_WIDTH*5-1:0] pack_d;
        input [IN_WIDTH-1:0] d0,d1,d2,d3,d4;
        begin pack_d = {d4,d3,d2,d1,d0}; end
    endfunction
    function [W_WIDTH*3-1:0] pack_f;
        input [W_WIDTH-1:0] f0,f1,f2;
        begin pack_f = {f2,f1,f0}; end
    endfunction
    function [ACC_WIDTH*3-1:0] pack_r;
        input [ACC_WIDTH-1:0] r0,r1,r2;
        begin pack_r = {r2,r1,r0}; end
    endfunction

    // ---- task: 安全复位 ----
    task do_reset;
        begin
            rst_n = 0; start_tile = 0;
            repeat(3) @(posedge clk);
            @(negedge clk); rst_n = 1;
            @(negedge clk);
        end
    endtask

    // ---- task: 发送一个tile并等待完成 ----
    reg [ACC_WIDTH-1:0] exp0, exp1, exp2;
    integer test_pass;

    task run_tile_and_check;
        input [IN_WIDTH*5-1:0] d0, d1, d2;
        input [W_WIDTH*3-1:0] f0, f1, f2;
        input [ACC_WIDTH*3-1:0] ptop, pprev;
        input [ACC_WIDTH-1:0] e0, e1, e2;
        input [80*8-1:0] test_name;
        begin
            $display("=== %0s ===", test_name);
            // 数据+start同时发出, scheduler有PRELOAD状态自动处理一拍预取
            @(negedge clk);
            ifmap_row0 = d0; ifmap_row1 = d1; ifmap_row2 = d2;
            filter_row0 = f0; filter_row1 = f1; filter_row2 = f2;
            psum_top = ptop; prev_partial = pprev;
            start_tile = 1;
            @(negedge clk);
            start_tile = 0;

            wait(tile_done == 1'b1);

            if (acc_result[0*ACC_WIDTH +: ACC_WIDTH] != e0 ||
                acc_result[1*ACC_WIDTH +: ACC_WIDTH] != e1 ||
                acc_result[2*ACC_WIDTH +: ACC_WIDTH] != e2) begin
                $display("  FAIL: result=(%0d,%0d,%0d) expected=(%0d,%0d,%0d)",
                    acc_result[0*ACC_WIDTH +: ACC_WIDTH],
                    acc_result[1*ACC_WIDTH +: ACC_WIDTH],
                    acc_result[2*ACC_WIDTH +: ACC_WIDTH], e0, e1, e2);
                test_pass = 0;
            end else $display("  PASS");

            wait(tile_done == 1'b0);  // 等待DONE→IDLE
            #(CLK_PERIOD * 3);
        end
    endtask

    // ========================================================================
    // 主测试
    // ========================================================================
    initial begin
        ifmap_row0 = 0; ifmap_row1 = 0; ifmap_row2 = 0;
        filter_row0 = 0; filter_row1 = 0; filter_row2 = 0;
        psum_top = 0; prev_partial = 0;
        test_pass = 1;

        do_reset;

        // ====================================
        // Test1: RS Dataflow Tile
        // 对应Python: pe_array_test.py TEST 2
        // ifmap_row0=[1,2,3,4,5], filter_row0=[1,2,3]
        // ifmap_row1=[6,7,8,9,10], filter_row1=[4,5,6]
        // ifmap_row2=[11,12,13,14,15], filter_row2=[7,8,9]
        // 手算: PE(2,0).result = [411,456,501]
        // ====================================
        run_tile_and_check(
            pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5),
            pack_d(5'd6, 5'd7, 5'd8, 5'd9, 5'd10),
            pack_d(5'd11,5'd12,5'd13,5'd14,5'd15),
            pack_f(8'd1, 8'd2, 8'd3),
            pack_f(8'd4, 8'd5, 8'd6),
            pack_f(8'd7, 8'd8, 8'd9),
            pack_r(16'd0, 16'd0, 16'd0),
            pack_r(16'd0, 16'd0, 16'd0),
            16'd411, 16'd456, 16'd501,
            "Test1: RS Dataflow [411,456,501]"
        );

        // ====================================
        // Test2: Simple Tile (all-ones filter, same data)
        // ifmap rows all = [1,2,3,4,5], filter all = [1,1,1], psum=[0,0,0]
        // 每行dot=[6,9,12], 3行累加=[18,27,36]
        // ====================================
        run_tile_and_check(
            pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5),
            pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5),
            pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5),
            pack_f(8'd1, 8'd1, 8'd1),
            pack_f(8'd1, 8'd1, 8'd1),
            pack_f(8'd1, 8'd1, 8'd1),
            pack_r(16'd0, 16'd0, 16'd0),
            pack_r(16'd0, 16'd0, 16'd0),
            16'd18, 16'd27, 16'd36,
            "Test2: All-ones [18,27,36]"
        );

        // ====================================
        // Test3: Accumulation with prev_partial
        // Same tile as Test2, but prev_partial=[100,200,300]
        // Expected: [18+100, 27+200, 36+300] = [118,227,336]
        // ====================================
        run_tile_and_check(
            pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5),
            pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5),
            pack_d(5'd1, 5'd2, 5'd3, 5'd4, 5'd5),
            pack_f(8'd1, 8'd1, 8'd1),
            pack_f(8'd1, 8'd1, 8'd1),
            pack_f(8'd1, 8'd1, 8'd1),
            pack_r(16'd0, 16'd0, 16'd0),
            pack_r(16'd100, 16'd200, 16'd300),
            16'd118, 16'd227, 16'd336,
            "Test3: Accumulation [118,227,336]"
        );

        // ====================================
        if (test_pass)
            $display("\n=== ALL SYSTEM TESTS PASSED ===");
        else
            $display("\n=== SOME SYSTEM TESTS FAILED ===");

        #(CLK_PERIOD * 5);
        $finish;
    end

endmodule
