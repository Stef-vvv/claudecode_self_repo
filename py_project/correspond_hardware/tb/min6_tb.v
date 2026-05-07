`timescale 1ns / 1ps
module min6_tb;
    localparam IW=5, WW=8, AW=16, CLK=10;
    reg clk=0, rst_n=0, st=0;
    reg [IW*18-1:0] irp=0;
    reg [WW*3-1:0] fr0=0, fr1=0, fr2=0;
    reg [AW*3-1:0] pt=0;
    wire st_g, ni_d, td, af;
    wire [AW*3-1:0] ar0;

    Scheduler_6array #(.IN_WIDTH(IW),.W_WIDTH(WW),.ACC_WIDTH(AW))
        sch (.clk(clk),.rst_n(rst_n),.start_tile(st),
             .ifmap_row_padded(irp),.filter_row0(fr0),.filter_row1(fr1),.filter_row2(fr2),
             .psum_top(pt),.start_global(st_g),.new_in_data(ni_d),
             .out_data0(),.out_data1(),.out_data2(),.out_data3(),.out_data4(),.out_data5(),
             .out_filter(),.out_psum_top(),
             .arr_result0(0),.arr_result1(0),.arr_result2(0),
             .arr_result3(0),.arr_result4(0),.arr_result5(0),
             .arr_finished0(0),.arr_finished1(0),.arr_finished2(0),
             .arr_finished3(0),.arr_finished4(0),.arr_finished5(0),
             .any_finished(af),.tile_done(td));

    always #(CLK/2) clk=~clk;

    initial begin
        rst_n=0; #(CLK*3); rst_n=1; @(negedge clk);

        irp=0; fr0={8'd1,8'd2,8'd3}; fr1={8'd4,8'd5,8'd6}; fr2={8'd7,8'd8,8'd9};
        @(negedge clk); st=1;

        // Print at every posedge
        repeat(12) begin
            @(posedge clk);
            $display("T=%0t: st_g=%b ni_d=%b td=%b af=%b",
                $time, st_g, ni_d, td, af);
        end
        $finish;
    end
endmodule
