`timescale 1ns / 1ps
module probe_tb;
    localparam IW=5, WW=8, AW=16, OW=16, CLK=10;
    reg clk=0, rst_n=0, st=0;
    reg [IW*18-1:0] irp=0;
    reg [WW*3-1:0] fr0=0, fr1=0, fr2=0;
    reg [AW*3-1:0] pt=0;
    reg [AW*OW-1:0] pv=0;
    wire st_g, ni_d, td, af;
    wire [IW*5-1:0] d0;

    // 直接例化scheduler_6array + 1个PE阵列, 监控所有中间信号
    Scheduler_6array #(.IN_WIDTH(IW),.W_WIDTH(WW),.ACC_WIDTH(AW))
        sch (.clk(clk),.rst_n(rst_n),.start_tile(st),
             .ifmap_row_padded(irp),.filter_row0(fr0),.filter_row1(fr1),.filter_row2(fr2),
             .psum_top(pt),.start_global(st_g),.new_in_data(ni_d),
             .out_data0(d0),.out_data1(),.out_data2(),.out_data3(),.out_data4(),.out_data5(),
             .out_filter(),.out_psum_top(),
             .arr_result0(0),.arr_result1(0),.arr_result2(0),.arr_result3(0),.arr_result4(0),.arr_result5(0),
             .arr_finished0(0),.arr_finished1(0),.arr_finished2(0),.arr_finished3(0),.arr_finished4(0),.arr_finished5(0),
             .any_finished(af),.tile_done(td));

    wire [AW*3-1:0] ar0;
    wire af0;
    PE_Array #(.N(3),.IN_WIDTH(IW),.W_WIDTH(WW),.ACC_WIDTH(AW))
        a0 (.clk(clk),.rst_n(rst_n),.start_global(st_g),.new_in_data(ni_d),
            .in_data(d0),.in_filter(0),.in_psum_top(0),
            .out_result(ar0),.out_finished(af0));

    always #(CLK/2) clk=~clk;

    function [IW*18-1:0] pk; input [IW-1:0] pL,c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13,c14,c15,pR;
        begin pk={pR,c15,c14,c13,c12,c11,c10,c9,c8,c7,c6,c5,c4,c3,c2,c1,c0,pL}; end endfunction
    function [WW*3-1:0] pf; input [WW-1:0] a,b,c; begin pf={c,b,a}; end endfunction

    initial begin
        rst_n=0; #(CLK*3); rst_n=1; @(negedge clk);

        @(negedge clk);
        irp=pk(5'd1, 5'd1,5'd2,5'd3,5'd4,5'd5,5'd6,5'd7,5'd8,5'd9,5'd10,5'd11,5'd12,5'd13,5'd14,5'd15,5'd16, 5'd0);
        fr0=pf(8'd1,8'd2,8'd3); fr1=pf(8'd4,8'd5,8'd6); fr2=pf(8'd7,8'd8,8'd9);
        pt=0; st=1; @(negedge clk); st=0;

        // 逐周期监控
        repeat(30) begin
            @(posedge clk);
            $display("T=%0t: st_g=%b ni_d=%b d0=(%0d,%0d,%0d,%0d,%0d) af0=%b td=%b ar0=(%0d,%0d,%0d)",
                $time, st_g, ni_d, d0[0*IW+:IW],d0[1*IW+:IW],d0[2*IW+:IW],d0[3*IW+:IW],d0[4*IW+:IW],
                af0, td, ar0[0*AW+:AW],ar0[1*AW+:AW],ar0[2*AW+:AW]);
            if (td) begin
                $display("TILE DONE!");
                // stop after 5 more cycles
                repeat(5) @(posedge clk);
                $finish;
            end
        end
        $display("TIMEOUT");
        $finish;
    end
endmodule
