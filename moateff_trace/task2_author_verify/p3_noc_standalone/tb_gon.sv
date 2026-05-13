// ===========================================================================
// tb_gon.sv — Module test: standalone GON (2025_8_23)
// GON reads from PE outputs. enable_out selects which PE drives the bus.
// ===========================================================================
`timescale 1ns / 1ps

module tb_gon;

    localparam CLK = 10, DW = 64, RTW = 4, CTW = 4, NR = 3, NC = 2;

    reg clk=0, rst=1, en=0;
    reg [RTW-1:0] row_tag, row_id [0:NR-1];
    reg [CTW-1:0] col_tag, col_id [0:NR-1][0:NC-1];
    reg [DW-1:0] pe_data [0:NR-1][0:NC-1];     // data from each PE
    reg [0:NC-1] pe_rdy [0:NR-1];               // each PE is ready to send
    wire [0:NC-1] pe_en [0:NR-1];               // GON tells PE: "you, output now"
    wire gout_rdy;                                // GON: "data is on the bus"

    always #(CLK/2) clk = ~clk;

    gon #(.DATA_WIDTH(DW),.ROW_TAG_WIDTH(RTW),.COL_TAG_WIDTH(CTW),
          .NUM_OF_ROWS(NR),.NUM_OF_COLS(NC))
    UUT (.clk,.reset(rst),.row_tag,.col_tag,.row_id,.col_id,
         .data_in(pe_data),.ready_in(pe_rdy),.enable_in(en),
         .enable_out(pe_en),.ready_out(gout_rdy));

    integer err = 0;

    task chk;
        input string m;
        input int xr, xc;  // -1 = none enabled
        begin
            @(negedge clk); #1;
            for (int r=0;r<NR;r=r+1) for (int c=0;c<NC;c=c+1) begin
                if (r==xr && c==xc) begin
                    if (pe_en[r][c] !== 1'b1) begin
                        $display("[FAIL] %s: PE[%0d][%0d] en=%b exp=1", m, r, c, pe_en[r][c]);
                        err=err+1;
                    end else if (gout_rdy !== 1'b1) begin
                        $display("[FAIL] %s: PE[%0d][%0d] en=1 but ready_out=%b", m, r, c, gout_rdy);
                        err=err+1;
                    end
                end else begin
                    if (pe_en[r][c] === 1'b1) begin
                        $display("[FAIL] %s: PE[%0d][%0d] unexpectedly en=1", m, r, c);
                        err=err+1;
                    end
                end
            end
            if (err==0) $display("[PASS] %s", m); else err=0;
        end
    endtask

    initial begin
        $display("=== GON Module Test (Standalone %0dx%0d) ===", NR, NC);
        rst=1; repeat(5) @(posedge clk); rst=0; repeat(3) @(posedge clk);

        // Config: row_id[r]=r, col_id[r][c]=c (same as GIN test)
        for(int r=0;r<NR;r=r+1) row_id[r]=r[RTW-1:0];
        for(int r=0;r<NR;r=r+1) for(int c=0;c<NC;c=c+1) col_id[r][c]=c[CTW-1:0];
        // All PEs have data ready
        for(int r=0;r<NR;r=r+1) for(int c=0;c<NC;c=c+1) begin
            pe_data[r][c]=64'h0000_0000_0000_0000 + r*16'h1000 + c;
            pe_rdy[r][c]=1;
        end
        en=1; @(posedge clk);

        // T1: select PE[0][0]
        $display("\n-- T1: tag (0,0) selects PE[0][0] --");
        row_tag=0; col_tag=0; chk("T1", 0, 0);

        // T2: select PE[2][1]
        $display("\n-- T2: tag (2,1) selects PE[2][1] --");
        row_tag=2; col_tag=1; chk("T2", 2, 1);

        // T3: select PE[1][0]
        $display("\n-- T3: tag (1,0) selects PE[1][0] --");
        row_tag=1; col_tag=0; chk("T3", 1, 0);

        // T4: no match (row tag 7 → no PE)
        $display("\n-- T4: tag (7,0) → no match --");
        row_tag=7; col_tag=0; chk("T4", -1, -1);
        if (gout_rdy !== 1'b0)
            $display("[FAIL] T4: gout_rdy=%b exp=0 (no PE should output)", gout_rdy);
        else $display("[PASS] T4: gout_rdy=0 (no data)");

        // T5: PE not ready
        $display("\n-- T5: PE[0][0] not ready → no output --");
        pe_rdy[0][0]=0; row_tag=0; col_tag=0; chk("T5", -1, -1);
        pe_rdy[0][0]=1;

        // T6: recovery
        $display("\n-- T6: tag (0,0) after recovery --");
        row_tag=0; col_tag=0; chk("T6 recovery", 0, 0);

        $display("\n========================================");
        if (err==0) $display("ALL GON TESTS PASSED (%0dx%0d)", NR, NC);
        else $display("FAILED: %0d errors", err);
        $display("========================================");
        $stop;
    end
endmodule
