// ===========================================================================
// tb_debug_v4.sv — Parameter dump: verify scan chain → NoC parameter flow
// ===========================================================================
`timescale 1ns / 1ps

import shared_pkg::*;
import cfg_pkg::*;

module tb_debug_v4;

    localparam CORE_CLK_PERIOD = 10;
    localparam LINK_CLK_PERIOD = 30;

    reg core_clk = 0;
    reg link_clk = 0;
    reg reset_n = 0;

    always #(CORE_CLK_PERIOD/2) core_clk = ~core_clk;
    always #(LINK_CLK_PERIOD/2) link_clk = ~link_clk;

    assign shared_pkg::core_clk = core_clk;
    assign shared_pkg::link_clk = link_clk;
    assign shared_pkg::re_from_dram = 0;
    assign shared_pkg::rdata_from_dram = 0;
    assign shared_pkg::valid_from_dram = 0;
    assign shared_pkg::start_backward = 0;
    assign shared_pkg::words_num = 0;
    assign shared_pkg::start_forward = 0;
    assign shared_pkg::transfer_type = 0;

    eyeriss #(
        .DATA_WIDTH_IFMAP(16),.ROW_TAG_WIDTH_IFMAP(4),.COL_TAG_WIDTH_IFMAP(5),
        .DATA_WIDTH_FILTER(64),.ROW_TAG_WIDTH_FILTER(4),.COL_TAG_WIDTH_FILTER(4),
        .DATA_WIDTH_PSUM(64),.ROW_TAG_WIDTH_PSUM(4),.COL_TAG_WIDTH_PSUM(4),
        .NUM_OF_ROWS(12),.NUM_OF_COLS(14),
        .GIN_FIFO_DEPTH(16),.GON_FIFO_DEPTH(16),
        .IFMAP_FIFO_DEPTH(4),.FILTER_FIFO_DEPTH(8),.PSUM_FIFO_DEPTH(8),
        .IFMAP_SPAD_DEPTH(12),.FILTER_SPAD_DEPTH(224),.PSUM_SPAD_DEPTH(24),
        .H_WIDTH(8),.W_WIDTH(8),.R_WIDTH(4),.S_WIDTH(4),
        .E_WIDTH(6),.F_WIDTH(6),.C_WIDTH(10),.M_WIDTH(10),
        .N_WIDTH(3),.U_WIDTH(3),
        .m_WIDTH(8),.n_WIDTH(3),.e_WIDTH(8),
        .p_WIDTH(5),.q_WIDTH(3),.r_WIDTH(2),.t_WIDTH(3),
        .ROW_MAJOR(1),.ADDR_WIDTH(20),.DATA_WIDTH(16),
        .FIFO_WIDTH(64),.FIFO_DEPTH(8),
        .IFMAP_GLB_DEPTH(7945),.FILTER_GLB_DEPTH(3872),
        .PSUM_GLB_DEPTH(46656),.BIAS_GLB_DEPTH(64)
    ) DUT (
        .core_clk, .link_clk, .reset(~reset_n),
        .scan_en(shared_pkg::scan_en), .scan_in(shared_pkg::scan_in), .scan_out(),
        .start(1'b0), .busy(), .done(),
        .start_pass(shared_pkg::start_pass), .pass_done(),
        .ofmap_dump(), .dump_done(1'b0),
        .words_num(), .start_forward(), .transfer_type(),
        .re_from_dram(), .rdata_from_dram(), .valid_from_dram(),
        .start_backward(), .we_to_dram(), .wdata_to_dram(), .transfer_done(),
        .filter_ids(), .filter_channel_ids(),
        .ifmap_ids(), .ifmap_channel_ids(),
        .psum_ids(), .psum_channel_ids()
    );

    initial begin
        $display("=== tb_debug_v4: Parameter Dump ===");

        // Reset
        reset_n = 0;
        repeat(20) @(posedge core_clk);
        reset_n = 1;
        repeat(10) @(posedge core_clk);

        // Dump BEFORE scan chain (should be zeros)
        $display("\n--- BEFORE scan chain (all zeros expected) ---");
        dump_params();

        // Load scan chain
        cfg_scan_chain("H:/moateff_trace/debug_campaign/serial_lsb_first_lf.txt");
        $display("\n[%0t] Scan chain loaded", $time);

        // Dump AFTER scan chain
        $display("\n--- AFTER scan chain (scan_en=%b) ---", shared_pkg::scan_en);
        dump_params();

        // Check if scan_en truly went to 0
        repeat(10) @(posedge core_clk);
        $display("\n--- 10 cycles later (scan_en=%b) ---", shared_pkg::scan_en);
        dump_params();

        // Also dump scheduler parameters separately
        $display("\n--- Scheduler parameters ---");
        $display("E=%0d C=%0d M=%0d N=%0d", DUT.SCHEDULER.E, DUT.SCHEDULER.C,
            DUT.SCHEDULER.M, DUT.SCHEDULER.N);
        $display("m=%0d n=%0d e=%0d p=%0d q=%0d r=%0d t=%0d",
            DUT.SCHEDULER.m, DUT.SCHEDULER.n, DUT.SCHEDULER.e,
            DUT.SCHEDULER.p, DUT.SCHEDULER.q, DUT.SCHEDULER.r, DUT.SCHEDULER.t);

        // Expected (tiny config): H=8,W=8,R=3,S=3,E=6,F=6,C=1,M=1,N=1,U=1
        //                       m=1,n=1,e=6,p=1,q=1,r=1,t=1
        $display("\n--- Expected (tiny config) ---");
        $display("H=8 W=8 R=3 S=3 E=6 F=6 C=1 M=1 N=1 U=1");
        $display("m=1 n=1 e=6 p=1 q=1 r=1 t=1");

        $display("\n=== v4 complete ===");
        $stop;
    end

    // Dump scan_chain register outputs (from EYERISS internal scan chain)
    task dump_params;
        begin
            // Scan chain outputs from EYERISS — these are the wires that
            // connect SCAN_CHAIN outputs to SCHEDULER/PROCESSING inputs
            $display("SCAN: H=%0d W=%0d R=%0d S=%0d E=%0d F=%0d",
                DUT.SCAN_CHAIN.H, DUT.SCAN_CHAIN.W,
                DUT.SCAN_CHAIN.R, DUT.SCAN_CHAIN.S,
                DUT.SCAN_CHAIN.E, DUT.SCAN_CHAIN.F);
            $display("SCAN: C=%0d M=%0d N=%0d U=%0d",
                DUT.SCAN_CHAIN.C, DUT.SCAN_CHAIN.M,
                DUT.SCAN_CHAIN.N, DUT.SCAN_CHAIN.U);
            $display("SCAN: m=%0d n=%0d e=%0d p=%0d q=%0d r=%0d t=%0d",
                DUT.SCAN_CHAIN.m, DUT.SCAN_CHAIN.n,
                DUT.SCAN_CHAIN.e, DUT.SCAN_CHAIN.p,
                DUT.SCAN_CHAIN.q, DUT.SCAN_CHAIN.r,
                DUT.SCAN_CHAIN.t);
        end
    endtask

endmodule
