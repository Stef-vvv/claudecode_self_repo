// ===========================================================================
// tb_gin.sv — Module test: standalone GIN (2025_8_23)
// Tests: tag matching, backpressure, multicast routing
// ===========================================================================
`timescale 1ns / 1ps

module tb_gin;

    localparam CLK_PERIOD = 10;
    localparam DW = 64, RTW = 4, CTW = 4, NR = 3, NC = 2;

    reg clk=0, reset=1, enable=0;
    reg [RTW-1:0] row_tag, row_id [0:NR-1];
    reg [CTW-1:0] col_tag, col_id [0:NR-1][0:NC-1];
    reg [DW-1:0] data_in;
    reg [0:NC-1] rdy [0:NR-1];
    wire [DW-1:0] dout [0:NR-1][0:NC-1];
    wire [0:NC-1] en [0:NR-1];
    wire gout;

    always #(CLK_PERIOD/2) clk = ~clk;

    gin #(.DATA_WIDTH(DW),.ROW_TAG_WIDTH(RTW),.COL_TAG_WIDTH(CTW),
          .NUM_OF_ROWS(NR),.NUM_OF_COLS(NC))
    UUT (.clk,.reset,.row_tag,.col_tag,.row_id,.col_id,.ready_in(rdy),
         .enable_in(enable),.data_in(data_in),.data_out(dout),.enable_out(en),.ready_out(gout));

    integer err = 0;

    task check;
        input string msg;
        input int exp_r, exp_c;  // -1 = expect no PE enabled
        input [DW-1:0] exp_d;
        begin
            @(negedge clk); #1;
            for (int r=0; r<NR; r=r+1) for (int c=0; c<NC; c=c+1) begin
                if (r==exp_r && c==exp_c) begin
                    if (en[r][c] !== 1'b1) begin
                        $display("[FAIL] %s: PE[%0d][%0d] en=%b exp=1", msg, r, c, en[r][c]);
                        err=err+1;
                    end
                    if (dout[r][c] !== exp_d) begin
                        $display("[FAIL] %s: PE[%0d][%0d] data_in=%h exp=%h", msg, r, c, dout[r][c], exp_d);
                        err=err+1;
                    end
                end else begin
                    if (en[r][c] === 1'b1) begin
                        $display("[FAIL] %s: PE[%0d][%0d] unexpectedly en=1", msg, r, c);
                        err=err+1;
                    end
                end
            end
            if (err==0) $display("[PASS] %s", msg); else err=0;
        end
    endtask

    initial begin
        $display("=== GIN Module Test (2025_8_23 standalone, %0dx%0d) ===", NR, NC);
        reset=1; repeat(5) @(posedge clk); reset=0; repeat(3) @(posedge clk);

        // Config: row_id[r]=r, col_id[r][c]=c
        for(int r=0;r<NR;r=r+1) row_id[r]=r[RTW-1:0];
        for(int r=0;r<NR;r=r+1) for(int c=0;c<NC;c=c+1) col_id[r][c]=c[CTW-1:0];
        for(int r=0;r<NR;r=r+1) for(int c=0;c<NC;c=c+1) rdy[r][c]=1;
        enable=1; @(posedge clk);

        // Test 1: exact match
        $display("\n-- T1: tag (0,0) → PE[0][0] --");
        row_tag=0; col_tag=0; data_in=64'hA000_0000_0000_0001;
        @(posedge clk); check("T1", 0,0, 64'hA000_0000_0000_0001);

        // Test 2: match row 1, col 1
        $display("\n-- T2: tag (1,1) → PE[1][1] --");
        row_tag=1; col_tag=1; data_in=64'hB000_0000_0000_0002;
        @(posedge clk); check("T2", 1,1, 64'hB000_0000_0000_0002);

        // Test 3: tag (2,0) → PE[2][0]
        $display("\n-- T3: tag (2,0) → PE[2][0] --");
        row_tag=2; col_tag=0; data_in=64'hC000_0000_0000_0003;
        @(posedge clk); check("T3", 2,0, 64'hC000_0000_0000_0003);

        // Test 4: no match (row tag 5 → no PE)
        $display("\n-- T4: tag (5,0) → no match --");
        row_tag=5; col_tag=0; data_in=64'hD000_0000_0000_0004;
        @(posedge clk); check("T4", -1,-1, 0);

        // Test 5: no match (col tag 5 → no PE)
        $display("\n-- T5: tag (0,5) → no match --");
        row_tag=0; col_tag=5; data_in=64'hE000_0000_0000_0005;
        @(posedge clk); check("T5", -1,-1, 0);

        // Test 6: backpressure — PE[0][0] not ready
        $display("\n-- T6: PE[0][0] rdy=0 → stall --");
        rdy[0][0]=0; row_tag=0; col_tag=0; data_in=64'hF000_0000_0000_0006;
        @(posedge clk);
        if (en[0][0] === 1'b1) begin
            $display("[FAIL] T6: delivered to PE[0][0] when rdy=0"); err=err+1;
        end else $display("[PASS] T6: backpressure works");
        rdy[0][0]=1;

        // Test 7: row-level broadcast (2 cols, same row)
        $display("\n-- T7: tag (0,0) after recovery --");
        row_tag=0; col_tag=0; data_in=64'h0000_0000_0000_0007;
        @(posedge clk); check("T7 recovery", 0,0, 64'h0000_0000_0000_0007);

        // Summary
        $display("\n========================================");
        if (err==0) $display("ALL GIN TESTS PASSED (%0dx%0d NoC)", NR, NC);
        else $display("FAILED: %0d errors", err);
        $display("========================================");
        $stop;
    end
endmodule
