`timescale 1ns / 1ps
module dbg7_tb;
    localparam IW=5, WW=8, AW=16, CLK=10;
    reg clk=0, rst_n=0;
    reg st_g=0, ni_d=0;
    reg [IW*5-1:0] d0=0;
    reg [WW*3-1:0] flt=0;
    reg [AW*3-1:0] pt=0;
    wire [AW*3-1:0] ar;
    wire af;

    PE_Array #(.N(3),.IN_WIDTH(IW),.W_WIDTH(WW),.ACC_WIDTH(AW))
        arr (.clk(clk),.rst_n(rst_n),.start_global(st_g),.new_in_data(ni_d),
             .in_data(d0),.in_filter(flt),.in_psum_top(pt),
             .out_result(ar),.out_finished(af));

    always #(CLK/2) clk=~clk;

    function [IW*5-1:0] pd; input [IW-1:0] a,b,c,e,f; begin pd={f,e,c,b,a}; end endfunction
    function [WW*3-1:0] pf; input [WW-1:0] a,b,c; begin pf={c,b,a}; end endfunction

    initial begin
        rst_n=0; #(CLK*3); rst_n=1; @(negedge clk);

        $display("=== Direct PE Array with data pre-loaded 1 cycle early ===");
        // Pre-load data
        @(negedge clk); d0=pd(5'd1,5'd2,5'd3,5'd4,5'd5); flt=pf(8'd1,8'd2,8'd3); pt=0;
        // Next cycle: assert start
        @(negedge clk); st_g=1; ni_d=1;
        // Keep data same for row1
        @(negedge clk); st_g=0;
        @(negedge clk); ni_d=0;

        wait(af==1'b1);
        $display("Result=(%0d,%0d,%0d)", ar[0*AW+:AW], ar[1*AW+:AW], ar[2*AW+:AW]);

        // Test2: start at same cycle as data
        rst_n=0; #(CLK*3); rst_n=1; @(negedge clk);
        @(negedge clk); d0=pd(5'd1,5'd2,5'd3,5'd4,5'd5); flt=pf(8'd1,8'd2,8'd3);
        st_g=1; ni_d=1; pt=0;
        @(negedge clk); st_g=0; d0=pd(5'd6,5'd7,5'd8,5'd9,5'd10); flt=pf(8'd4,8'd5,8'd6);
        @(negedge clk); d0=pd(5'd11,5'd12,5'd13,5'd14,5'd15); flt=pf(8'd7,8'd8,8'd9);
        @(negedge clk); ni_d=0;

        wait(af==1'b1);
        $display("Result=(%0d,%0d,%0d) expect=(411,456,501)", ar[0*AW+:AW], ar[1*AW+:AW], ar[2*AW+:AW]);

        $finish;
    end
endmodule
