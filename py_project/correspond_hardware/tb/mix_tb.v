`timescale 1ns / 1ps
module mix_tb;
    localparam IW=5, WW=8, AW=16, OW=16, CLK=10;
    reg clk=0, rst_n=0;
    // 单阵列Scheduler (已验证)
    reg st=0;
    reg [IW*5-1:0] im0=0, im1=0, im2=0;
    reg [WW*3-1:0] fr0=0, fr1=0, fr2=0;
    reg [AW*3-1:0] pt=0;
    wire s_st, s_ni;
    wire [IW*5-1:0] s_d;
    wire [WW*3-1:0] s_f;
    wire [AW*3-1:0] s_p;
    wire [AW*3-1:0] s_tr;
    wire s_td;

    Scheduler #(.IN_WIDTH(IW),.W_WIDTH(WW),.ACC_WIDTH(AW))
        sch (.clk(clk),.rst_n(rst_n),.start_tile(st),
             .ifmap_row0(im0),.ifmap_row1(im1),.ifmap_row2(im2),
             .filter_row0(fr0),.filter_row1(fr1),.filter_row2(fr2),
             .psum_top(pt),.start_global(s_st),.new_in_data(s_ni),
             .out_data(s_d),.out_filter(s_f),.out_psum_top(s_p),
             .array_result(s_tr),.array_finished(1'b0),.tile_result(),.tile_done(s_td));

    // 2个PE阵列 (共享同一数据源, 测试连通性)
    wire [AW*3-1:0] ar0, ar1;
    wire af0, af1;

    PE_Array #(.N(3),.IN_WIDTH(IW),.W_WIDTH(WW),.ACC_WIDTH(AW))
        a0 (.clk(clk),.rst_n(rst_n),.start_global(s_st),.new_in_data(s_ni),
            .in_data(s_d),.in_filter(s_f),.in_psum_top(s_p),
            .out_result(ar0),.out_finished(af0));

    PE_Array #(.N(3),.IN_WIDTH(IW),.W_WIDTH(WW),.ACC_WIDTH(AW))
        a1 (.clk(clk),.rst_n(rst_n),.start_global(s_st),.new_in_data(s_ni),
            .in_data(s_d),.in_filter(s_f),.in_psum_top(s_p),
            .out_result(ar1),.out_finished(af1));

    always #(CLK/2) clk=~clk;

    function [IW*5-1:0] pd; input [IW-1:0] a,b,c,e,f; begin pd={f,e,c,b,a}; end endfunction
    function [WW*3-1:0] pf; input [WW-1:0] a,b,c; begin pf={c,b,a}; end endfunction

    initial begin
        rst_n=0; #(CLK*3); rst_n=1; @(negedge clk);

        // 数据: 与单阵列测试相同 [1..5],[6..10],[11..15], filter [1,2,3],[4,5,6],[7,8,9]
        @(negedge clk);
        im0=pd(5'd1,5'd2,5'd3,5'd4,5'd5);
        im1=pd(5'd6,5'd7,5'd8,5'd9,5'd10);
        im2=pd(5'd11,5'd12,5'd13,5'd14,5'd15);
        fr0=pf(8'd1,8'd2,8'd3); fr1=pf(8'd4,8'd5,8'd6); fr2=pf(8'd7,8'd8,8'd9);
        pt=0; st=1; @(negedge clk); st=0;

        wait(af0==1'b1);
        $display("Array0: (%0d,%0d,%0d) expect=(411,456,501)",
            ar0[0*AW+:AW], ar0[1*AW+:AW], ar0[2*AW+:AW]);
        $display("Array1: (%0d,%0d,%0d) (same data, same result)",
            ar1[0*AW+:AW], ar1[1*AW+:AW], ar1[2*AW+:AW]);

        if (ar0[0*AW+:AW]==16'd411 && ar0[1*AW+:AW]==16'd456 && ar0[2*AW+:AW]==16'd501)
            $display("Array0 PASS");
        else $display("Array0 FAIL");

        $finish;
    end
endmodule
