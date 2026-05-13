// ===========================================================================
// tb_scan_final.sv — Isolated full tiny config test (LSB-first)
// ===========================================================================
`timescale 1ns / 1ps
module tb_scan_final;
    localparam CLK=10;
    reg clk=0, rst=0, en=0, si=0;
    wire [7:0] H,W,m; wire [3:0] R,S; wire [5:0] E,F,e;
    wire [9:0] C,M; wire [2:0] N,U,n,q,t; wire [4:0] p; wire [1:0] r; wire so;
    always #(CLK/2) clk=~clk;

    scan_chain #(.H_WIDTH(8),.W_WIDTH(8),.R_WIDTH(4),.S_WIDTH(4),
        .E_WIDTH(6),.F_WIDTH(6),.C_WIDTH(10),.M_WIDTH(10),.N_WIDTH(3),.U_WIDTH(3),
        .m_WIDTH(8),.n_WIDTH(3),.e_WIDTH(6),.p_WIDTH(5),.q_WIDTH(3),.r_WIDTH(2),.t_WIDTH(3))
    UUT (.clk,.reset(rst),.scan_en(en),.scan_in(si),.scan_out(so),
         .H,.W,.R,.S,.E,.F,.C,.M,.N,.U,.m,.n,.e,.p,.q,.r,.t);

    task shift(input string bits);
        integer i;
        begin
            en=1;
            for(i=0;i<bits.len();i=i+1) begin
                si=(bits[i]=="1");  // drive before negedge
                @(negedge clk);      // scan_ff captures on negedge
            end
            en=0;
            @(negedge clk); // latch q
        end
    endtask

    initial begin
        $display("=== Scan Chain Final ===");
        rst=1; repeat(5) @(negedge clk); rst=0; repeat(3) @(negedge clk);

        // Test just H+W first (16 bits)
        $display("Loading H+W LSB-first...");
        shift("00010000"+"00010000");
        $display("H=%0d W=%0d (expect 8,8)", H, W);

        // Verify the chain still works after more bits
        shift("1100"+"1100");  // R+S
        $display("H=%0d W=%0d R=%0d S=%0d (expect 8,8,3,3)", H, W, R, S);

        // Full 92-bit test
        rst=1; repeat(5) @(negedge clk); rst=0; repeat(3) @(negedge clk);
        $display("\nLoading full 92-bit LSB-first tiny config...");
        shift(
            "00010000"+"00010000"+"1100"+"1100"+"011000"+"011000"+
            "1000000000"+"1000000000"+"100"+"100"+
            "10000000"+"100"+"011000"+"10000"+"100"+"10"+"100"
        );
        $display("H=%0d W=%0d R=%0d S=%0d E=%0d F=%0d", H,W,R,S,E,F);
        $display("C=%0d M=%0d N=%0d U=%0d", C,M,N,U);
        $display("m=%0d n=%0d e=%0d p=%0d q=%0d r=%0d t=%0d", m,n,e,p,q,r,t);
        $display("Match: %s",
            (H==8&&W==8&&R==3&&S==3&&E==6&&F==6&&C==1&&M==1&&N==1&&U==1&&
             m==1&&n==1&&e==6&&p==1&&q==1&&r==1&&t==1)?"YES":"NO");
        $stop;
    end
endmodule
