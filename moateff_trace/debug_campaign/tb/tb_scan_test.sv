// ===========================================================================
// tb_scan_test.sv — Manual scan chain loading + parameter verify
// ===========================================================================
`timescale 1ns / 1ps
module tb_scan_test;
    localparam CLK=10;
    reg clk=0, rst=0, en=0, si=0;
    wire [7:0] H; wire [7:0] W; wire [3:0] R; wire [3:0] S;
    wire [5:0] E; wire [5:0] F; wire [9:0] C; wire [9:0] M;
    wire [2:0] N; wire [2:0] U; wire [7:0] m; wire [2:0] n;
    wire [5:0] e; wire [4:0] p; wire [2:0] q; wire [1:0] r; wire [2:0] t;
    wire so;
    always #(CLK/2) clk=~clk;

    scan_chain #(.H_WIDTH(8),.W_WIDTH(8),.R_WIDTH(4),.S_WIDTH(4),
        .E_WIDTH(6),.F_WIDTH(6),.C_WIDTH(10),.M_WIDTH(10),
        .N_WIDTH(3),.U_WIDTH(3),.m_WIDTH(8),.n_WIDTH(3),
        .e_WIDTH(6),.p_WIDTH(5),.q_WIDTH(3),.r_WIDTH(2),.t_WIDTH(3))
    UUT (.clk,.reset(rst),.scan_en(en),.scan_in(si),.scan_out(so),
         .H,.W,.R,.S,.E,.F,.C,.M,.N,.U,.m,.n,.e,.p,.q,.r,.t);

    task shift_bits;
        input string bits;
        integer i;
        begin
            en=1;
            for(i=0;i<bits.len();i=i+1) begin
                @(posedge clk);     // drive on posedge
                si=(bits[i]=="1");
                // si stable during next half-cycle → captured at negedge
            end
            @(posedge clk);
            en=0;
            @(negedge clk);
        end
    endtask

    initial begin
        $display("=== Standalone Scan Chain Test ===");
        rst=1; repeat(5) @(negedge clk); rst=0; repeat(2) @(negedge clk);

        // Test 1a: MSB-first "00001000" = H=8
        $display("\nT1a: Load H=8 MSB-first: 00001000");
        shift_bits("00001000");
        $display("H=%0d (exp 8) W=%0d", H, W);

        // Test 1b: LSB-first "00010000" = H=8
        rst=1; repeat(5) @(negedge clk); rst=0; repeat(2) @(negedge clk);
        $display("\nT1b: Load H=8 LSB-first: 00010000");
        shift_bits("00010000");
        $display("H=%0d (exp 8) W=%0d", H, W);

        // Test 1c: completely reversed: "00010000"→reversed→"00001000"... wait that's same
        // Let's try: load one "1" into bit position 0: "10000000"
        rst=1; repeat(5) @(negedge clk); rst=0; repeat(2) @(negedge clk);
        $display("\nT1c: Load single 1 at MSB: 10000000");
        shift_bits("10000000");
        $display("H=%0d (exp 128) W=%0d", H, W);

        // T1d: load LSB first: "00000001"
        rst=1; repeat(5) @(negedge clk); rst=0; repeat(2) @(negedge clk);
        $display("\nT1d: Load single 1 at LSB: 00000001");
        shift_bits("00000001");
        $display("H=%0d (exp 1) W=%0d", H, W);

        // Test 2: clear and load 16 bits for H+W = 8+8
        rst=1; repeat(5) @(negedge clk); rst=0; repeat(2) @(negedge clk);
        $display("\nT2: Load H=8,W=8 (MSB first each)");
        shift_bits("00001000"+"00001000");
        $display("H=%0d (exp 8) W=%0d (exp 8)", H, W);

        // Test 5: FULL tiny config LSB-first (each param internally reversed)
        rst=1; repeat(5) @(negedge clk); rst=0; repeat(2) @(negedge clk);
        $display("\nT5: Full tiny config - LSB-first per param");
        // H=8 LSB:"00010000" W=8 LSB:"00010000" R=3 LSB:"1100" S=3 LSB:"1100"
        // E=6 LSB:"011000" F=6 LSB:"011000" C=1 LSB:"1000000000" M=1 LSB:"1000000000"
        // N=1 LSB:"100" U=1 LSB:"100" m=1 LSB:"10000000" n=1 LSB:"100"
        // e=6 LSB:"011000" p=1 LSB:"10000" q=1 LSB:"100" r=1 LSB:"10" t=1 LSB:"100"
        shift_bits(
            "00010000"+"00010000"+"1100"+"1100"+"011000"+"011000"+
            "1000000000"+"1000000000"+"100"+"100"+
            "10000000"+"100"+"011000"+"10000"+"100"+"10"+"100"
        );
        $display("H=%0d (8) W=%0d (8) R=%0d (3) S=%0d (3) E=%0d (6) F=%0d (6)", H,W,R,S,E,F);
        $display("C=%0d (1) M=%0d (1) N=%0d (1) U=%0d (1)", C,M,N,U);
        $display("m=%0d (1) n=%0d (1) e=%0d (6) p=%0d (1) q=%0d (1) r=%0d (1) t=%0d (1)", m,n,e,p,q,r,t);
        $display("ALL CORRECT? %s",
            (H==8&&W==8&&R==3&&S==3&&E==6&&F==6&&C==1&&M==1&&N==1&&U==1&&m==1&&n==1&&e==6&&p==1&&q==1&&r==1&&t==1)?"YES":"NO");

        $stop;
    end
endmodule
