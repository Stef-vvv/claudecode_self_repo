`timescale 1ns / 1ps
module dbg6_tb;
    localparam IW=5, WW=8, AW=16, CLK=10;
    reg clk=0, rst_n=0, st=0;
    reg [IW*18-1:0] irp=0;
    reg [WW*3-1:0] fr0=0, fr1=0, fr2=0;
    reg [AW*3-1:0] pt=0;
    wire st_g, ni_d;
    wire [IW*5-1:0] d0;
    wire [WW*3-1:0] flt;
    wire td;

    Scheduler_6array #(.IN_WIDTH(IW),.W_WIDTH(WW),.ACC_WIDTH(AW))
        sch (.clk(clk),.rst_n(rst_n),.start_tile(st),
             .ifmap_row_padded(irp),.filter_row0(fr0),.filter_row1(fr1),.filter_row2(fr2),
             .psum_top(pt),
             .start_global(st_g),.new_in_data(ni_d),
             .out_data0(d0),.out_data1(),.out_data2(),.out_data3(),.out_data4(),.out_data5(),
             .out_filter(flt),.out_psum_top(),.arr_result0(0),.arr_result1(0),.arr_result2(0),
             .arr_result3(0),.arr_result4(0),.arr_result5(0),.arr_finished0(0),.arr_finished1(0),
             .arr_finished2(0),.arr_finished3(0),.arr_finished4(0),.arr_finished5(0),
             .any_finished(),.tile_done(td));

    always #(CLK/2) clk=~clk;

    initial begin
        rst_n=0; #(CLK*3); rst_n=1; @(negedge clk);

        // Set data + start
        irp = {5'd0, 5'd16,5'd15,5'd14,5'd13,5'd12,5'd11,5'd10,5'd9,5'd8,
               5'd7,5'd6,5'd5,5'd4,5'd3,5'd2,5'd1, 5'd0}; // padR,c15..c0,padL
        fr0={8'd7,8'd8,8'd9}; // filter row0
        pt=0;
        @(negedge clk); st=1;
        @(negedge clk); st=0;

        // Wait and print each cycle
        repeat(8) begin
            @(negedge clk);
            $display("T=%0t: st_g=%b ni_d=%b d0=(%0d,%0d,%0d,%0d,%0d) flt=(%0d,%0d,%0d) td=%b",
                $time, st_g, ni_d,
                d0[0*IW+:IW],d0[1*IW+:IW],d0[2*IW+:IW],d0[3*IW+:IW],d0[4*IW+:IW],
                flt[0*WW+:WW],flt[1*WW+:WW],flt[2*WW+:WW], td);
        end
        $finish;
    end
endmodule
