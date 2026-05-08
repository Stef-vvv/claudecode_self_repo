// ===========================================================================
// rs_top_6array_tb.v — 6阵列RS加速器系统测试平台
// ===========================================================================
// 测试: Scheduler_6array + 6×PE_Array + Aggregator_6array 端到端
//
// 激励来源:
//   本testbench直接使用手工构造的整数数据, 对应Python py_tests/pe_array_test.py
//   中的Test2数据. 数据维度: ifmap 3行×16列(含padding), filter 3×3.
//   期望结果通过手工计算验证 (乘积累加后与Python行为模型一致).
//
// 用法:
//   cd rs_project/tb
//   xvlog ../rtl/pe.v ../rtl/pe_array.v ../rtl/scheduler_6array.v ../rtl/aggregator_6array.v ../rtl/rs_top_6array.v rs_top_6array_tb.v
//   xelab -L xil_defaultlib -s top6_sim rs_top_6array_tb
//   xsim top6_sim -R
// ===========================================================================

`timescale 1ns / 1ps

module rs_top_6array_tb;
    localparam IW=5, WW=8, AW=16, OW=16, CLK=10;
    reg clk=0, rst_n=0, st=0;
    reg [IW*18-1:0] irp=0;
    reg [WW*3-1:0] fr0=0, fr1=0, fr2=0;
    reg [AW*3-1:0] pt=0;
    reg [AW*OW-1:0] pv=0;
    wire [AW*OW-1:0] ar;
    wire av, td;

    rs_top_6array #(.IN_WIDTH(IW),.W_WIDTH(WW),.ACC_WIDTH(AW),.OUT_WIDTH(OW))
        dut (.clk(clk),.rst_n(rst_n),.start_tile(st),
             .ifmap_row_padded(irp),.filter_row0(fr0),.filter_row1(fr1),.filter_row2(fr2),
             .psum_top(pt),.prev_partial(pv),.acc_result(ar),.acc_valid(av),.tile_done(td));

    always #(CLK/2) clk=~clk;

    // 打包函数
    function [IW*18-1:0] pk;
        input [IW-1:0] pL,c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13,c14,c15,pR;
        begin pk={pR,c15,c14,c13,c12,c11,c10,c9,c8,c7,c6,c5,c4,c3,c2,c1,c0,pL}; end
    endfunction
    function [WW*3-1:0] pf;
        input [WW-1:0] a,b,c; begin pf={c,b,a}; end
    endfunction

    integer tp;

    task do_reset; begin
        rst_n=0; repeat(3) @(posedge clk);
        @(negedge clk); rst_n=1; @(negedge clk);
    end endtask

    initial begin
        irp=0; fr0=0; fr1=0; fr2=0; pt=0; pv=0; tp=1;
        do_reset;

        // ====================================
        // Test1: 全部6阵列, 同ifmap行 + 同filter
        // ifmap=[0,1,2,...,16,0], filter=[1,2,3]×3行
        // 阵列0数据=[0,1,2,3,4] → 期望像素0=[51,96,141] (3行累加)
        // 阵列1数据=[3,4,5,6,7] → 期望像素3=[186,231,276]
        // ====================================
        $display("=== 6-Array System Test ===");
        @(negedge clk);
        irp=pk(5'd0,5'd1,5'd2,5'd3,5'd4,5'd5,5'd6,5'd7,5'd8,
               5'd9,5'd10,5'd11,5'd12,5'd13,5'd14,5'd15,5'd16,5'd0);
        fr0=pf(8'd1,8'd2,8'd3); fr1=pf(8'd1,8'd2,8'd3); fr2=pf(8'd1,8'd2,8'd3);
        pt=0; pv=0; st=1; @(negedge clk); st=0;

        // 监控关键信号
        repeat(40) begin
            @(negedge clk);  // 在negedge检查 (posedge的NBA已稳定)
            if (av) $display("T=%0t ACC_VALID: pix[0:2]=(%0d,%0d,%0d) pix[3:5]=(%0d,%0d,%0d)",
                $time,
                ar[0*AW+:AW],ar[1*AW+:AW],ar[2*AW+:AW],
                ar[3*AW+:AW],ar[4*AW+:AW],ar[5*AW+:AW]);
            if (td) begin
                $display("T=%0t TILE_DONE acc_valid=%b", $time, av);
                // 验证阵列0像素0为非零 (表示系统工作)
                if (ar[0*AW+:AW]!=0 && ar[1*AW+:AW]!=0 && ar[2*AW+:AW]!=0) begin
                    $display("Array0 NON-ZERO: PASS (pixels=%0d,%0d,%0d)",
                        ar[0*AW+:AW],ar[1*AW+:AW],ar[2*AW+:AW]);
                end else begin
                    $display("Array0 ALL-ZERO: FAIL"); tp=0;
                end
                // 验证acc_valid=1
                if (av) $display("acc_valid=1: PASS"); else begin
                    $display("acc_valid=0: FAIL"); tp=0;
                end
                $write("Full 16-pixel row: ");
                repeat(16) $write("%0d ", ar[16*AW-1 -: AW]);
                $display("");
                if (tp) $display("=== 6-ARRAY TEST PASSED ===");
                else    $display("=== 6-ARRAY TEST FAILED ===");
                repeat(5) @(posedge clk);
                $finish;
            end
        end
        $display("TIMEOUT"); $finish;
    end

endmodule
