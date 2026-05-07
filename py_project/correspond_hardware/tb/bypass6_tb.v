`timescale 1ns / 1ps
module bypass6_tb;
    localparam IW=5, WW=8, AW=16, CLK=10;
    reg clk=0, rst_n=0, st_g=0, ni_d=0;
    reg [IW*5-1:0] d0=0, d1=0;
    reg [WW*3-1:0] flt=0;
    reg [AW*3-1:0] pt=0;
    wire [AW*3-1:0] ar0, ar1;
    wire af0, af1;

    // 只测试2个阵列
    PE_Array #(.N(3),.IN_WIDTH(IW),.W_WIDTH(WW),.ACC_WIDTH(AW))
        arr0 (.clk(clk),.rst_n(rst_n),.start_global(st_g),.new_in_data(ni_d),
              .in_data(d0),.in_filter(flt),.in_psum_top(pt),
              .out_result(ar0),.out_finished(af0));

    PE_Array #(.N(3),.IN_WIDTH(IW),.W_WIDTH(WW),.ACC_WIDTH(AW))
        arr1 (.clk(clk),.rst_n(rst_n),.start_global(st_g),.new_in_data(ni_d),
              .in_data(d1),.in_filter(flt),.in_psum_top(pt),
              .out_result(ar1),.out_finished(af1));

    always #(CLK/2) clk=~clk;

    function [IW*5-1:0] pd; input [IW-1:0] a,b,c,e,f; begin pd={f,e,c,b,a}; end endfunction
    function [WW*3-1:0] pf; input [WW-1:0] a,b,c; begin pf={c,b,a}; end endfunction

    initial begin
        rst_n=0; #(CLK*3); rst_n=1; @(negedge clk);

        // 测试: 两个阵列不同的5元素切片
        // arr0: [1,2,3,4,5] → 与单阵列测试相同
        // arr1: [6,7,8,9,10] → 不同数据
        @(negedge clk); st_g=1; ni_d=1;
        d0=pd(5'd1,5'd2,5'd3,5'd4,5'd5);
        d1=pd(5'd6,5'd7,5'd8,5'd9,5'd10);
        flt=pf(8'd1,8'd2,8'd3);
        pt=0;

        @(negedge clk); st_g=0;
        d0=pd(5'd1,5'd2,5'd3,5'd4,5'd5); // 相同(模拟同ifmap行)
        d1=pd(5'd6,5'd7,5'd8,5'd9,5'd10);
        flt=pf(8'd4,8'd5,8'd6);

        @(negedge clk);
        d0=pd(5'd1,5'd2,5'd3,5'd4,5'd5);
        d1=pd(5'd6,5'd7,5'd8,5'd9,5'd10);
        flt=pf(8'd7,8'd8,8'd9);

        @(negedge clk); ni_d=0;

        wait(af0==1'b1 && af1==1'b1);
        $display("Arr0: (%0d,%0d,%0d) expect=(411,456,501)",
            ar0[0*AW+:AW],ar0[1*AW+:AW],ar0[2*AW+:AW]);
        $display("Arr1: (%0d,%0d,%0d)",
            ar1[0*AW+:AW],ar1[1*AW+:AW],ar1[2*AW+:AW]);
        $finish;
    end
endmodule
