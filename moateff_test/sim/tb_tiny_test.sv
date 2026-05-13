// ===========================================================================
// tb_tiny_test.sv — Tiny layer end-to-end self-checking test
//
// Test layer: 8×8 ifmap, 3×3 filter, 1 channel, 1 filter, stride 1, no pad
// OFM: 6×6
// Uses 3 PEs (rows 0..2, col 0) of the 12×14 array
// All data fits in GLB (no DRAM needed)
// ===========================================================================
`timescale 1ns / 1ps

import shared_pkg::*;

module tb_tiny_test;

    eyeriss #(
        .DATA_WIDTH_IFMAP(DATA_WIDTH_IFMAP),
        .ROW_TAG_WIDTH_IFMAP(ROW_TAG_WIDTH_IFMAP),
        .COL_TAG_WIDTH_IFMAP(COL_TAG_WIDTH_IFMAP),
        .DATA_WIDTH_FILTER(DATA_WIDTH_FILTER),
        .ROW_TAG_WIDTH_FILTER(ROW_TAG_WIDTH_FILTER),
        .COL_TAG_WIDTH_FILTER(COL_TAG_WIDTH_FILTER),
        .DATA_WIDTH_PSUM(DATA_WIDTH_PSUM),
        .ROW_TAG_WIDTH_PSUM(ROW_TAG_WIDTH_PSUM),
        .COL_TAG_WIDTH_PSUM(COL_TAG_WIDTH_PSUM),
        .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS),
        .GIN_FIFO_DEPTH(GIN_FIFO_DEPTH),
        .GON_FIFO_DEPTH(GON_FIFO_DEPTH),
        .IFMAP_FIFO_DEPTH(IFMAP_FIFO_DEPTH),
        .FILTER_FIFO_DEPTH(FILTER_FIFO_DEPTH),
        .PSUM_FIFO_DEPTH(PSUM_FIFO_DEPTH),
        .IFMAP_SPAD_DEPTH(IFMAP_SPAD_DEPTH),
        .FILTER_SPAD_DEPTH(FILTER_SPAD_DEPTH),
        .PSUM_SPAD_DEPTH(PSUM_SPAD_DEPTH),
        .H_WIDTH(H_WIDTH), .W_WIDTH(W_WIDTH), .R_WIDTH(R_WIDTH), .S_WIDTH(S_WIDTH),
        .E_WIDTH(E_WIDTH), .F_WIDTH(F_WIDTH), .C_WIDTH(C_WIDTH), .M_WIDTH(M_WIDTH),
        .N_WIDTH(N_WIDTH), .U_WIDTH(U_WIDTH),
        .m_WIDTH(m_WIDTH), .n_WIDTH(n_WIDTH), .e_WIDTH(e_WIDTH),
        .p_WIDTH(p_WIDTH), .q_WIDTH(q_WIDTH), .r_WIDTH(r_WIDTH), .t_WIDTH(t_WIDTH),
        .ROW_MAJOR(ROW_MAJOR), .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .FIFO_WIDTH(FIFO_WIDTH), .FIFO_DEPTH(FIFO_DEPTH),
        .IFMAP_GLB_DEPTH(IFMAP_GLB_DEPTH), .FILTER_GLB_DEPTH(FILTER_GLB_DEPTH),
        .PSUM_GLB_DEPTH(PSUM_GLB_DEPTH), .BIAS_GLB_DEPTH(BIAS_GLB_DEPTH)
    ) DUT (
        .core_clk(core_clk), .link_clk(link_clk),
        .reset(reset),
        .scan_en(scan_en), .scan_in(scan_in), .scan_out(scan_out),
        .start(start), .busy(busy), .done(done),
        .start_pass(start_pass), .pass_done(pass_done),
        .ofmap_dump(ofmap_dump), .dump_done(dump_done),
        .words_num(words_num), .transfer_done(transfer_done),
        .start_forward(start_forward), .transfer_type(transfer_type),
        .re_from_dram(re_from_dram), .rdata_from_dram(rdata_from_dram),
        .valid_from_dram(valid_from_dram),
        .start_backward(start_backward), .we_to_dram(we_to_dram),
        .wdata_to_dram(wdata_to_dram),
        .filter_ids(filter_ids), .filter_channel_ids(filter_channel_ids),
        .ifmap_ids(ifmap_ids), .ifmap_channel_ids(ifmap_channel_ids),
        .psum_ids(psum_ids), .psum_channel_ids(psum_channel_ids)
    );

    // Clocks
    initial forever #(CORE_CLK_PERIOD/2.0) core_clk = ~core_clk;
    initial forever #(LINK_CLK_PERIOD/2.0) link_clk = ~link_clk;

    // ========================================================================
    // Debug: periodic status monitor
    // ========================================================================
    integer cycle_count;
    initial cycle_count = 0;
    always @(posedge core_clk) cycle_count = cycle_count + 1;

    // Print status every 5000 cycles or on key transitions
    always @(posedge core_clk) begin
        if (cycle_count % 5000 == 0 && cycle_count > 0) begin
            $display("[DEBUG] cycle=%0d start=%b busy=%b done=%b ofmap=%b pass_done=%b",
                     cycle_count, start, busy, done, ofmap_dump, pass_done);
        end
        if (ofmap_dump) $display("[DEBUG] ofmap_dump ↑ at cycle=%0d", cycle_count);
        if (done)       $display("[DEBUG] done ↑ at cycle=%0d", cycle_count);
        if (busy)       ; // quiet
    end

    // Timeout after 500K cycles
    always @(posedge core_clk) begin
        if (cycle_count > 500000) begin
            $display("[TB] TIMEOUT at cycle %0d — stopping", cycle_count);
            $stop;
        end
    end

    // ========================================================================
    // Test parameters
    // ========================================================================
    localparam TH = 8, TW = 8;    // ifmap height, width
    localparam TR = 3, TS = 3;    // filter height, width
    localparam TC = 1;            // input channels
    localparam TM = 1;            // output filters
    localparam TN = 1;            // batch
    localparam TU = 1;            // stride
    localparam TE = 6, TF = 6;    // OFM height, width

    // ========================================================================
    // Test data & golden reference (computed at compile time in testbench)
    // ========================================================================
    reg [15:0] ifmap_data [0:TH*TW-1];
    reg [15:0] filter_data [0:TR*TS-1];
    reg [15:0] expected_ofmap [0:TE*TF-1];
    integer h, w, r, s, oh, ow;
    integer gold_idx;

    // ========================================================================
    // Scan chain config (from serial_data.txt)
    // ========================================================================
    task automatic cfg_scan;
        int file, bit_val;
        string line;
        begin
            $display("[TB] Configuring scan chain (tiny test layer)...");
            file = $fopen("H:/moateff_test/config/tiny/serial_data.txt", "r");
            if (file == 0) begin
                $display("[ERROR] Cannot open serial_data.txt");
                $stop;
            end
            scan_en = 1;
            while (!$feof(file)) begin
                line = "";
                void'($fgets(line, file));
                if (line.len() > 0) begin
                    $sscanf(line, "%d", bit_val);
                    scan_in = bit_val;
                    @(posedge core_clk);
                end
            end
            scan_en = 0;
            $fclose(file);
            $display("[TB] Scan chain configured.");
        end
    endtask

    // ========================================================================
    // Load GLB with test data
    // GLB layout (row-major, interleaved across 4 banks):
    //   IFMAP: addr = h*W + w  (for single channel/batch)
    //   FILTER: addr = r*S + s
    //   BIAS: addr = m
    //   OFMAP: addr = oh*E + ow
    // Each 64-bit GLB word packs 4 consecutive 16-bit values
    // ========================================================================
    task automatic load_glb;
        integer addr_64, base;
        reg [63:0] word;
        reg [15:0] v0, v1, v2, v3;
        begin
            // --- IFMAP: TH*TW = 64 values → 16 64-bit words ---
            $display("[TB] Loading IFMAP (64 values)...");
            base = 0;
            addr_64 = 0;
            for (h = 0; h < TH; h = h + 1) begin
                for (w = 0; w < TW; w = w + 4) begin
                    v0 = (w+0 < TW) ? ifmap_data[h*TW + w + 0] : 16'd0;
                    v1 = (w+1 < TW) ? ifmap_data[h*TW + w + 1] : 16'd0;
                    v2 = (w+2 < TW) ? ifmap_data[h*TW + w + 2] : 16'd0;
                    v3 = (w+3 < TW) ? ifmap_data[h*TW + w + 3] : 16'd0;
                    DUT.GLB.U1_IFMAP.U0_0.mem[addr_64] = v0;
                    DUT.GLB.U1_IFMAP.U0_1.mem[addr_64] = v1;
                    DUT.GLB.U1_IFMAP.U1_0.mem[addr_64] = v2;
                    DUT.GLB.U1_IFMAP.U1_1.mem[addr_64] = v3;
                    addr_64 = addr_64 + 1;
                end
            end
            $display("[TB] IFMAP loaded: %0d 64-bit words", addr_64);

            // --- FILTER: TR*TS = 9 values → 3 64-bit words ---
            $display("[TB] Loading FILTER (9 values)...");
            addr_64 = 0;
            for (r = 0; r < TR; r = r + 1) begin
                for (s = 0; s < TS; s = s + 4) begin
                    v0 = (s+0 < TS) ? filter_data[r*TS + s + 0] : 16'd0;
                    v1 = (s+1 < TS) ? filter_data[r*TS + s + 1] : 16'd0;
                    v2 = (s+2 < TS) ? filter_data[r*TS + s + 2] : 16'd0;
                    v3 = (s+3 < TS) ? filter_data[r*TS + s + 3] : 16'd0;
                    DUT.GLB.U2_FILTER.U0_0.mem[addr_64] = v0;
                    DUT.GLB.U2_FILTER.U0_1.mem[addr_64] = v1;
                    DUT.GLB.U2_FILTER.U1_0.mem[addr_64] = v2;
                    DUT.GLB.U2_FILTER.U1_1.mem[addr_64] = v3;
                    addr_64 = addr_64 + 1;
                end
            end
            $display("[TB] FILTER loaded: %0d 64-bit words", addr_64);

            // --- BIAS: 1 value → 1 64-bit word ---
            $display("[TB] Loading BIAS (1 value)...");
            DUT.GLB.U3_BIAS.U0_0.mem[0] = 16'd0;  // bias = 0
            DUT.GLB.U3_BIAS.U0_1.mem[0] = 16'd0;
            DUT.GLB.U3_BIAS.U1_0.mem[0] = 16'd0;
            DUT.GLB.U3_BIAS.U1_1.mem[0] = 16'd0;
            $display("[TB] BIAS loaded.");
        end
    endtask

    // ========================================================================
    // Verify output
    // ========================================================================
    task automatic verify_output;
        integer addr_64, base;
        reg [15:0] got [0:3];
        reg [15:0] exp [0:3];
        integer mismatch, match;
        begin
            $display("[TB] Verifying output...");
            mismatch = 0;
            match = 0;
            addr_64 = 0;
            for (oh = 0; oh < TF; oh = oh + 1) begin
                for (ow = 0; ow < TE; ow = ow + 4) begin
                    got[0] = DUT.GLB.U4_PSUM.U0_0.mem[addr_64];
                    got[1] = DUT.GLB.U4_PSUM.U0_1.mem[addr_64];
                    got[2] = DUT.GLB.U4_PSUM.U1_0.mem[addr_64];
                    got[3] = DUT.GLB.U4_PSUM.U1_1.mem[addr_64];

                    for (int k = 0; k < 4; k = k + 1) begin
                        if (ow + k < TE) begin
                            exp[k] = expected_ofmap[oh*TE + ow + k];
                            if (got[k] !== exp[k]) begin
                                if (mismatch < 10) begin
                                    $display("[MISMATCH] ofmap[%0d][%0d]: got=%0d exp=%0d",
                                             oh, ow+k, $signed(got[k]), $signed(exp[k]));
                                end
                                mismatch = mismatch + 1;
                            end else begin
                                match = match + 1;
                            end
                        end
                    end
                    addr_64 = addr_64 + 1;
                end
            end

            $display("========================================");
            $display("  Match:    %0d", match);
            $display("  Mismatch: %0d", mismatch);
            if (mismatch == 0)
                $display("  *** ALL MATCH — HARDWARE VERIFIED ***");
            else
                $display("  *** MISMATCHES FOUND ***");
            $display("========================================");
        end
    endtask

    // ========================================================================
    // Main test
    // ========================================================================
    initial begin
        $display("============================================");
        $display("[TB] Eyeriss v1 — Tiny Layer Self-Checking Test");
        $display("[TB] Layer: %0dx%0dx%0d + %0dx%0d filter -> %0dx%0d OFM",
                 TH, TW, TC, TR, TS, TE, TF);
        $display("============================================");

        // --- Generate test data ---
        // Simple ifmap: row-major values 0..63, scaled to Q3.13
        for (h = 0; h < TH; h = h + 1)
            for (w = 0; w < TW; w = w + 1)
                ifmap_data[h*TW + w] = (h * TW + w + 1) * 256;  // small integers in Q3.13

        // Simple filter: 3×3 identity-like pattern
        // Row 0: 1, 0, 0; Row 1: 0, 1, 0; Row 2: 0, 0, 1
        // Keep values small to avoid overflow
        filter_data[0] = 16'h0100;  // Q3.13 = 0.125
        filter_data[1] = 16'h0000;
        filter_data[2] = 16'h0000;
        filter_data[3] = 16'h0000;
        filter_data[4] = 16'h0200;  // Q3.13 = 0.25
        filter_data[5] = 16'h0000;
        filter_data[6] = 16'h0000;
        filter_data[7] = 16'h0000;
        filter_data[8] = 16'h0100;  // Q3.13 = 0.125

        // Compute golden reference: conv2d(ifmap, filter) with bias=0, stride=1
        $display("[TB] Computing golden reference...");
        for (oh = 0; oh < TF; oh = oh + 1) begin
            for (ow = 0; ow < TE; ow = ow + 1) begin
                integer acc;
                acc = 0;
                for (r = 0; r < TR; r = r + 1) begin
                    for (s = 0; s < TS; s = s + 1) begin
                        h = oh * TU + r;
                        w = ow * TU + s;
                        // Q3.13 MAC: multiply, then truncate lower 13 bits
                        // (a * b) >> 13 approximates fixed-point multiply
                        acc = acc + (($signed(ifmap_data[h*TW + w]) * $signed(filter_data[r*TS + s])) >>> 13);
                    end
                end
                expected_ofmap[oh*TE + ow] = acc[15:0];
            end
        end

        // Print expected output
        $display("[TB] Expected output (6×6):");
        for (oh = 0; oh < TF; oh = oh + 1) begin
            $write("  ");
            for (ow = 0; ow < TE; ow = ow + 1)
                $write("%5d ", $signed(expected_ofmap[oh*TE + ow]));
            $display("");
        end

        // --- Initialize ---
        initialize_dut();
        wait_core_cycle(1);
        reset = 1;
        wait_core_cycle(1);
        reset = 0;
        wait_core_cycle(2);

        // --- Load GLB ---
        load_glb();

        // --- Configure scan chain ---
        cfg_scan();

        // --- Start ---
        $display("[TB] Starting scheduler...");
        start = 1;
        wait_core_cycle(1);
        start = 0;

        start_pass = 1;

        // Wait for completion
        $display("[TB] Waiting for ofmap_dump...");
        wait(ofmap_dump);
        $display("[TB] ofmap_dump=1 at time %0t", $time);
        dump_done = 1;
        wait_core_cycle(1);
        dump_done = 0;

        wait(done);
        $display("[TB] done=1 at time %0t", $time);

        // Verify
        verify_output();

        $display("[TB] Simulation complete.");
        $stop;
    end

endmodule
