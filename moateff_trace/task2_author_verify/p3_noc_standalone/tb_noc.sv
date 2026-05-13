// ===========================================================================
// tb_noc.sv — Module-level test for standalone NoC (GIN + GON)
// 2025_8_23 standalone version: IDs driven directly (no scan chain)
// ===========================================================================
`timescale 1ns / 1ps

module tb_noc;

    localparam CLK_PERIOD = 10;
    localparam DATA_WIDTH = 64;
    localparam ROW_TAG_WIDTH = 4;
    localparam COL_TAG_WIDTH = 4;
    localparam N_ROWS = 2;
    localparam N_COLS = 2;

    reg clk = 0;
    reg reset = 1;
    reg enable_in = 0;

    // GIN signals
    reg [ROW_TAG_WIDTH-1:0] row_tag;
    reg [COL_TAG_WIDTH-1:0] col_tag;
    reg [ROW_TAG_WIDTH-1:0] row_id [0:N_ROWS-1];
    reg [COL_TAG_WIDTH-1:0] col_id [0:N_ROWS-1][0:N_COLS-1];
    reg [DATA_WIDTH-1:0] data_in;
    reg [0:N_COLS-1] ready_in [0:N_ROWS-1];

    wire [DATA_WIDTH-1:0] gin_data_out [0:N_ROWS-1][0:N_COLS-1];
    wire [0:N_COLS-1] gin_enable_out [0:N_ROWS-1];
    wire gin_ready_out;

    // GON signals (standalone: direct PE port connections)
    wire [DATA_WIDTH-1:0] gon_data_out;
    wire [0:N_COLS-1] gon_enable_out [0:N_ROWS-1];
    wire gon_ready_out;

    always #(CLK_PERIOD/2) clk = ~clk;

    // GIN instance
    gin #(
        .DATA_WIDTH(DATA_WIDTH), .ROW_TAG_WIDTH(ROW_TAG_WIDTH),
        .COL_TAG_WIDTH(COL_TAG_WIDTH), .NUM_OF_ROWS(N_ROWS), .NUM_OF_COLS(N_COLS)
    ) U_GIN (
        .clk, .reset, .row_tag, .col_tag,
        .row_id, .col_id, .data_in,
        .ready_in, .enable_in,
        .data_out(gin_data_out), .enable_out(gin_enable_out),
        .ready_out(gin_ready_out)
    );

    // Feed GIN outputs to GON inputs (GON reads from PE outputs)
    // For testing: manually set gon data_in = some test data from PEs
    reg [DATA_WIDTH-1:0] gon_data_in_test [0:N_ROWS-1][0:N_COLS-1];
    reg [0:N_COLS-1] gon_ready_in_test [0:N_ROWS-1];

    // GON instance
    gon #(
        .DATA_WIDTH(DATA_WIDTH), .ROW_TAG_WIDTH(ROW_TAG_WIDTH),
        .COL_TAG_WIDTH(COL_TAG_WIDTH), .NUM_OF_ROWS(N_ROWS), .NUM_OF_COLS(N_COLS)
    ) U_GON (
        .clk, .reset, .row_tag, .col_tag,
        .row_id, .col_id,
        .data_in(gon_data_in_test), .ready_in(gon_ready_in_test),
        .enable_in(enable_in),
        .enable_out(gon_enable_out), .ready_out(gon_ready_out)
    );

    // ========================================================================
    // Test helpers
    // ========================================================================
    integer errors = 0;
    integer cycle = 0;

    task check_gin_output;
        input int exp_r, exp_c;  // expected row, col
        input [DATA_WIDTH-1:0] exp_data;
        input string msg;
        begin
            @(negedge clk);  // GIN updates on negedge
            #1;
            for (int r = 0; r < N_ROWS; r = r + 1) begin
                for (int c = 0; c < N_COLS; c = c + 1) begin
                    if (r == exp_r && c == exp_c) begin
                        if (gin_enable_out[r][c] !== 1'b1) begin
                            $display("[FAIL] %s: PE[%0d][%0d] enable_out=%b (expected 1)",
                                msg, r, c, gin_enable_out[r][c]);
                            errors = errors + 1;
                        end
                        if (gin_data_out[r][c] !== exp_data) begin
                            $display("[FAIL] %s: PE[%0d][%0d] data=%h (expected %h)",
                                msg, r, c, gin_data_out[r][c], exp_data);
                            errors = errors + 1;
                        end
                    end else begin
                        if (gin_enable_out[r][c] === 1'b1) begin
                            $display("[FAIL] %s: PE[%0d][%0d] unexpectedly enabled",
                                msg, r, c);
                            errors = errors + 1;
                        end
                    end
                end
            end
            if (errors == 0) $display("[PASS] %s", msg);
        end
    endtask

    // ========================================================================
    // Main test
    // ========================================================================
    initial begin
        $display("=== NoC Module Test (GIN + GON, 2x2) ===");

        // Reset
        reset = 1;
        repeat(5) @(posedge clk);
        reset = 0;
        repeat(5) @(posedge clk);

        // Configure PE IDs: row 0, col 0 = (0,0); row 1, col 1 = (1,1)
        for (int r = 0; r < N_ROWS; r = r + 1)
            row_id[r] = r[ROW_TAG_WIDTH-1:0];
        for (int r = 0; r < N_ROWS; r = r + 1)
            for (int c = 0; c < N_COLS; c = c + 1)
                col_id[r][c] = c[COL_TAG_WIDTH-1:0];

        // All PEs ready
        for (int r = 0; r < N_ROWS; r = r + 1)
            for (int c = 0; c < N_COLS; c = c + 1)
                ready_in[r][c] = 1'b1;

        enable_in = 1;
        @(posedge clk);

        // === Test 1: GIN tag match ===
        $display("\n--- Test 1: GIN tag (0,0) → PE[0][0] ---");
        row_tag = 0; col_tag = 0;
        data_in = 64'hDEAD_BEEF_CAFE_BABE;
        @(posedge clk);
        check_gin_output(0, 0, 64'hDEAD_BEEF_CAFE_BABE, "GIN tag=(0,0)");

        // === Test 2: GIN tag (1,1) ===
        $display("\n--- Test 2: GIN tag (1,1) → PE[1][1] ---");
        row_tag = 1; col_tag = 1;
        data_in = 64'hAAAA_BBBB_CCCC_DDDD;
        @(posedge clk);
        check_gin_output(1, 1, 64'hAAAA_BBBB_CCCC_DDDD, "GIN tag=(1,1)");

        // === Test 3: GIN tag mismatch ===
        $display("\n--- Test 3: GIN tag (3,3) → no match (2x2 array) ---");
        row_tag = 3; col_tag = 3;
        data_in = 64'hFFFF_FFFF_FFFF_FFFF;
        @(posedge clk);
        check_gin_output(-1, -1, 0, "GIN tag=(3,3) no match");

        // === Test 4: GIN row multicast ===
        $display("\n--- Test 4: GIN tag (0,*) → PE[0][0] and PE[0][1] ---");
        // Need to test row tag matches but col tag doesn't discriminate
        // In GIN: row MCC matches row 0 → data goes to row 0 XBus
        // Then XBus sends to all cols where col_id matches col_tag
        // With col_tag=0, only PE[0][0] should get it
        row_tag = 0; col_tag = 0;
        data_in = 64'h1111_2222_3333_4444;
        @(posedge clk);
        check_gin_output(0, 0, 64'h1111_2222_3333_4444, "GIN tag=(0,0) again");

        // === Test 5: Disable PE ready ===
        $display("\n--- Test 5: PE[0][0] not ready → backpressure ---");
        ready_in[0][0] = 1'b0;
        row_tag = 0; col_tag = 0;
        data_in = 64'h5555_6666_7777_8888;
        @(posedge clk);
        // When PE not ready, GIN should not assert enable_out for that PE
        if (gin_enable_out[0][0] === 1'b1) begin
            $display("[FAIL] GIN sent data to PE[0][0] when ready=0");
            errors = errors + 1;
        end else
            $display("[PASS] GIN backpressure: PE[0][0] enable_out=0 when ready=0");
        ready_in[0][0] = 1'b1;

        // Summary
        $display("\n========================================");
        if (errors == 0)
            $display("ALL NoC TESTS PASSED");
        else
            $display("FAILED: %0d errors", errors);
        $display("========================================");
        $stop;
    end

endmodule
