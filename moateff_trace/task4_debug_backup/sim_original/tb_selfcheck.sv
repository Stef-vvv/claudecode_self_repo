// ===========================================================================
// tb_selfcheck.sv — Self-checking testbench for Eyeriss v1
// Loads synthetic data directly to GLB, runs simulation, compares output
// ===========================================================================
`timescale 1ns / 1ps

import shared_pkg::*;

module tb_selfcheck;

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
    // Load data into GLB via the designed Port-A write interface
    // We simulate what the interface_unit would do: write 64-bit words
    // to Port A of each GLB. Each 64-bit word splits across 4 banks.
    //
    // GLB Port A write interface:
    //   we_a = 1, addr_a, wdata_a = 64-bit
    //   Bank 0: wdata[15:0], Bank 1: wdata[31:16], etc.
    // ========================================================================

    task automatic load_glb_file;
        input string filepath;
        input integer base_addr;
        output integer words_written;
        int file;
        reg [FIFO_WIDTH-1:0] word;
        begin
            words_written = 0;
            file = $fopen(filepath, "r");
            if (file == 0) begin
                $display("[ERROR] Cannot open: %s", filepath);
                $stop;
            end
            while (!$feof(file)) begin
                if ($fscanf(file, "%b\n", word) == 1) begin
                    @(posedge core_clk);
                    // This writes to Port A — but we need to drive the GLB's
                    // we_a, addr_a, wdata_a signals. However, those are
                    // internal to interface_unit/glb_unit. We'll use a
                    // different approach below.
                    words_written++;
                end
            end
            $fclose(file);
        end
    endtask

    // ========================================================================
    // Simpler approach: use force to preload data, then release
    // The GLB dual_bram has: reg [15:0] mem [0:DEPTH-1]
    // We force each bank, then release after loading
    // ========================================================================

    task automatic preload_ifmap;
        int file, addr;
        reg [FIFO_WIDTH-1:0] word;
        begin
            $display("[TB] Preloading IFMAP GLB...");
            file = $fopen("H:/moateff_test/test_data/ifmap_64.txt", "r");
            if (file == 0) begin
                $display("[ERROR] Cannot open ifmap_64.txt");
                $stop;
            end
            addr = 0;
            while (!$feof(file) && addr < 2000) begin  // 7945/4 ≈ 1986 entries per bank
                if ($fscanf(file, "%b\n", word) == 1) begin
                    DUT.GLB.U1_IFMAP.U0_0.mem[addr] = word[15:0];
                    DUT.GLB.U1_IFMAP.U0_1.mem[addr] = word[31:16];
                    DUT.GLB.U1_IFMAP.U1_0.mem[addr] = word[47:32];
                    DUT.GLB.U1_IFMAP.U1_1.mem[addr] = word[63:48];
                    addr = addr + 1;
                end
            end
            $fclose(file);
            $display("[TB] IFMAP loaded: %0d words per bank", addr);
        end
    endtask

    task automatic preload_filter;
        int file, addr;
        reg [FIFO_WIDTH-1:0] word;
        begin
            $display("[TB] Preloading FILTER GLB...");
            file = $fopen("H:/moateff_test/test_data/filter_64.txt", "r");
            if (file == 0) begin
                $display("[ERROR] Cannot open filter_64.txt");
                $stop;
            end
            addr = 0;
            while (!$feof(file) && addr < 1000) begin  // 3872/4 = 968 entries per bank
                if ($fscanf(file, "%b\n", word) == 1) begin
                    DUT.GLB.U2_FILTER.U0_0.mem[addr] = word[15:0];
                    DUT.GLB.U2_FILTER.U0_1.mem[addr] = word[31:16];
                    DUT.GLB.U2_FILTER.U1_0.mem[addr] = word[47:32];
                    DUT.GLB.U2_FILTER.U1_1.mem[addr] = word[63:48];
                    addr = addr + 1;
                end
            end
            $fclose(file);
            $display("[TB] FILTER loaded: %0d words per bank", addr);
        end
    endtask

    task automatic preload_bias;
        int file, addr;
        reg [FIFO_WIDTH-1:0] word;
        begin
            $display("[TB] Preloading BIAS GLB...");
            file = $fopen("H:/moateff_test/test_data/bias_64.txt", "r");
            if (file == 0) begin
                $display("[ERROR] Cannot open bias_64.txt");
                $stop;
            end
            addr = 0;
            while (!$feof(file) && addr < 20) begin  // 64/4 = 16 entries
                if ($fscanf(file, "%b\n", word) == 1) begin
                    DUT.GLB.U3_BIAS.U0_0.mem[addr] = word[15:0];
                    DUT.GLB.U3_BIAS.U0_1.mem[addr] = word[31:16];
                    DUT.GLB.U3_BIAS.U1_0.mem[addr] = word[47:32];
                    DUT.GLB.U3_BIAS.U1_1.mem[addr] = word[63:48];
                    addr = addr + 1;
                end
            end
            $fclose(file);
            $display("[TB] BIAS loaded: %0d words per bank", addr);
        end
    endtask

    // ========================================================================
    // Scan chain configuration
    // ========================================================================
    task automatic cfg_scan;
        int file, bit_val;
        string line;
        begin
            $display("[TB] Configuring scan chain...");
            file = $fopen("H:/moateff_test/config/conv1/serial_data.txt", "r");
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
    // Check PSUM output
    // ========================================================================
    task automatic check_output;
        int file_exp, addr;
        reg [63:0] expected_word, got_word;
        integer mismatch, match;
        reg [15:0] eb0, eb1, eb2, eb3, gb0, gb1, gb2, gb3;
        begin
            $display("[TB] Checking results...");
            file_exp = $fopen("H:/moateff_test/test_data/expected_output_64.txt", "r");
            if (file_exp == 0) begin
                $display("[WARN] No expected output file — dumping first 20 PSUM words:");
                for (addr = 0; addr < 20; addr = addr + 1) begin
                    gb0 = DUT.GLB.U4_PSUM.U0_0.mem[addr];
                    gb1 = DUT.GLB.U4_PSUM.U0_1.mem[addr];
                    gb2 = DUT.GLB.U4_PSUM.U1_0.mem[addr];
                    gb3 = DUT.GLB.U4_PSUM.U1_1.mem[addr];
                    $display("  PSUM[%0d] = %04h_%04h_%04h_%04h", addr, gb3, gb2, gb1, gb0);
                end
                return;
            end

            mismatch = 0;
            match = 0;
            addr = 0;
            while (!$feof(file_exp)) begin
                if ($fscanf(file_exp, "%b\n", expected_word) == 1) begin
                    gb0 = DUT.GLB.U4_PSUM.U0_0.mem[addr];
                    gb1 = DUT.GLB.U4_PSUM.U0_1.mem[addr];
                    gb2 = DUT.GLB.U4_PSUM.U1_0.mem[addr];
                    gb3 = DUT.GLB.U4_PSUM.U1_1.mem[addr];
                    got_word = {gb3, gb2, gb1, gb0};

                    if (got_word !== expected_word) begin
                        if (mismatch < 5) begin
                            $display("[MISMATCH] addr=%0d", addr);
                            $display("  got: %016h (%04h %04h %04h %04h)", got_word, gb3, gb2, gb1, gb0);
                            $display("  exp: %016h", expected_word);
                        end
                        mismatch = mismatch + 1;
                    end else begin
                        match = match + 1;
                    end
                    addr = addr + 1;
                end
            end
            $fclose(file_exp);

            $display("========================================");
            $display("  Match:    %0d", match);
            $display("  Mismatch: %0d", mismatch);
            if (mismatch == 0)
                $display("  *** ALL MATCH - HARDWARE VERIFIED ***");
            else
                $display("  *** MISMATCHES FOUND ***");
            $display("========================================");
        end
    endtask

    // ========================================================================
    // Main test sequence
    // ========================================================================
    initial begin
        $display("============================================");
        $display("[TB] Eyeriss v1 Self-Checking Testbench");
        $display("============================================");

        // Init
        initialize_dut();
        #(CORE_CLK_PERIOD);
        reset = 1;
        #(CORE_CLK_PERIOD);
        reset = 0;
        #(CORE_CLK_PERIOD);

        // Preload GLB with test data
        preload_ifmap();
        preload_filter();
        preload_bias();

        // Configure scan chain
        cfg_scan();

        // Start scheduler
        $display("[TB] Starting scheduler...");
        start = 1;
        #(CORE_CLK_PERIOD);
        start = 0;

        // Start processing
        start_pass = 1;

        // Wait for ofmap_dump
        $display("[TB] Waiting for ofmap_dump...");
        wait(ofmap_dump);
        $display("[TB] ofmap_dump=1 at time %0t", $time);
        dump_done = 1;
        #(CORE_CLK_PERIOD);
        dump_done = 0;

        // Wait for done
        wait(done);
        $display("[TB] done=1 at time %0t", $time);

        // Check output
        check_output();

        $display("[TB] Simulation complete.");
        $stop;
    end

endmodule
