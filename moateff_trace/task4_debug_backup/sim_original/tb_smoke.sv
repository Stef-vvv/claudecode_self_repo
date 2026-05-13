// ===========================================================================
// tb_smoke.sv — Minimal smoke test: verify scheduler FSM runs
// Uses original Conv1 config, no data needed
// ===========================================================================
`timescale 1ns / 1ps

import shared_pkg::*;

module tb_smoke;

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

    initial forever #(CORE_CLK_PERIOD/2.0) core_clk = ~core_clk;
    initial forever #(LINK_CLK_PERIOD/2.0) link_clk = ~link_clk;

    integer cycle;
    initial cycle = 0;
    always @(posedge core_clk) cycle = cycle + 1;

    // Monitor key signals
    always @(posedge core_clk) begin
        if (cycle % 10000 == 0 || done || ofmap_dump || pass_done)
            $display("[%0d] start=%b busy=%b done=%b ofmap=%b pass=%b",
                     cycle, start, busy, done, ofmap_dump, pass_done);
    end

    // Timeout after 2M cycles (~200s wall clock)
    always @(posedge core_clk) if (cycle > 2000000) begin
        $display("[TB] TIMEOUT at cycle %0d", cycle);
        $stop;
    end

    task automatic cfg_scan;
        int file, bit_val;
        string line;
        begin
            $display("[TB] Configuring scan chain (Conv1 config)...");
            file = $fopen("H:/moateff_test/config/conv1/serial_data.txt", "r");
            if (file == 0) begin $display("[ERROR] No config file"); $stop; end
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
            $display("[TB] Scan chain configured (%0d cycles)", cycle);
        end
    endtask

    initial begin
        $display("[TB] Smoke test — scheduler FSM only");
        initialize_dut();
        wait_core_cycle(1);
        reset = 1; wait_core_cycle(1); reset = 0;
        wait_core_cycle(2);

        cfg_scan();

        $display("[TB] Starting...");
        start = 1;
        wait_core_cycle(1);
        start = 0;

        start_pass = 1;

        wait(ofmap_dump || cycle > 100000);
        if (ofmap_dump) begin
            $display("[TB] ofmap_dump=1 at cycle %0d", cycle);
            dump_done = 1;
            wait_core_cycle(1);
            dump_done = 0;
        end

        wait(done || cycle > 200000);
        if (done) $display("[TB] done=1 at cycle %0d", cycle);
        else $display("[TB] TIMEOUT waiting for done");

        $display("[TB] Smoke test complete.");
        $stop;
    end

endmodule
