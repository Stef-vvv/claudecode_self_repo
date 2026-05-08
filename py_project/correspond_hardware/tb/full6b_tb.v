`timescale 1ns / 1ps
module full6b_tb;
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

    function [IW*18-1:0] pk; input [IW-1:0] pL,c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11,c12,c13,c14,c15,pR;
        begin pk={pR,c15,c14,c13,c12,c11,c10,c9,c8,c7,c6,c5,c4,c3,c2,c1,c0,pL}; end endfunction
    function [WW*3-1:0] pf; input [WW-1:0] a,b,c; begin pf={c,b,a}; end endfunction

    initial begin
        rst_n=0; #(CLK*3); rst_n=1; @(negedge clk);

        @(negedge clk);
        irp=pk(5'd0,5'd1,5'd2,5'd3,5'd4,5'd5,5'd6,5'd7,5'd8,5'd9,5'd10,5'd11,5'd12,5'd13,5'd14,5'd15,5'd16,5'd0);
        fr0=pf(8'd1,8'd2,8'd3); fr1=pf(8'd4,8'd5,8'd6); fr2=pf(8'd7,8'd8,8'd9);
        pt=0; pv=0;
        st=1; @(negedge clk); st=0;

        // 在negedge检查 (此时posedge的NBA已稳定)
        repeat(40) begin
            @(negedge clk);
            if (av) $display("T=%0t: ACC_VALID! pixel[0:2]=(%0d,%0d,%0d) pixel[3:5]=(%0d,%0d,%0d)",
                $time, ar[0*AW+:AW],ar[1*AW+:AW],ar[2*AW+:AW],
                ar[3*AW+:AW],ar[4*AW+:AW],ar[5*AW+:AW]);
            if (td) begin
                $display("T=%0t: TILE_DONE! acc_valid=%b", $time, av);
                if (ar!=0) $display("*** FULL 6-ARRAY SYSTEM WORKING! ***");
                else $display("ALL ZEROS");
                $write("Full row: ");
                repeat(16) $write("%0d ", ar[16*AW-1 -: AW]);
                $display("");
                repeat(5) @(posedge clk);
                $finish;
            end
        end
        $display("TIMEOUT"); $finish;
    end
endmodule
