// ===========================================================================
// tb_debug_v2.sv — Minimal extension of proven tb_smoke structure
// Uses: shared_pkg tb-style connections + cfg_pkg for scan chain
// Adds: GLB backdoor data + start_pass pulse
// ===========================================================================
`timescale 1ns / 1ps

import shared_pkg::*;
import cfg_pkg::*;

module tb_debug_v2;

    localparam CORE_CLK_PERIOD = 10;
    localparam LINK_CLK_PERIOD = 30;

    reg core_clk = 0;
    reg link_clk = 0;
    reg reset_n = 0;
    reg start = 0;

    always #(CORE_CLK_PERIOD/2) core_clk = ~core_clk;
    always #(LINK_CLK_PERIOD/2) link_clk = ~link_clk;

    // Connect shared_pkg signals (same pattern as original TB)
    assign shared_pkg::core_clk = core_clk;
    assign shared_pkg::link_clk = link_clk;
    assign shared_pkg::re_from_dram = 0;
    assign shared_pkg::rdata_from_dram = 0;
    assign shared_pkg::valid_from_dram = 0;
    assign shared_pkg::start_backward = 0;
    assign shared_pkg::words_num = 0;
    assign shared_pkg::start_forward = 0;
    assign shared_pkg::transfer_type = 0;

    wire [9:0] filter_ids_0, filter_ids_1, filter_channel_ids_0, filter_channel_ids_1;
    wire [9:0] ifmap_channel_ids_0, ifmap_channel_ids_1, psum_channel_ids_0, psum_channel_ids_1;
    wire [2:0] ifmap_ids_0, ifmap_ids_1, psum_ids_0, psum_ids_1;

    eyeriss #(
        .DATA_WIDTH_IFMAP(DATA_WIDTH_IFMAP), .ROW_TAG_WIDTH_IFMAP(ROW_TAG_WIDTH_IFMAP),
        .COL_TAG_WIDTH_IFMAP(COL_TAG_WIDTH_IFMAP), .DATA_WIDTH_FILTER(DATA_WIDTH_FILTER),
        .ROW_TAG_WIDTH_FILTER(ROW_TAG_WIDTH_FILTER), .COL_TAG_WIDTH_FILTER(COL_TAG_WIDTH_FILTER),
        .DATA_WIDTH_PSUM(DATA_WIDTH_PSUM), .ROW_TAG_WIDTH_PSUM(ROW_TAG_WIDTH_PSUM),
        .COL_TAG_WIDTH_PSUM(COL_TAG_WIDTH_PSUM), .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS), .GIN_FIFO_DEPTH(GIN_FIFO_DEPTH),
        .GON_FIFO_DEPTH(GON_FIFO_DEPTH), .IFMAP_FIFO_DEPTH(IFMAP_FIFO_DEPTH),
        .FILTER_FIFO_DEPTH(FILTER_FIFO_DEPTH), .PSUM_FIFO_DEPTH(PSUM_FIFO_DEPTH),
        .IFMAP_SPAD_DEPTH(IFMAP_SPAD_DEPTH), .FILTER_SPAD_DEPTH(FILTER_SPAD_DEPTH),
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
        .core_clk, .link_clk, .reset(~reset_n),
        .scan_en(shared_pkg::scan_en), .scan_in(shared_pkg::scan_in),
        .scan_out(),
        .start(start), .busy(), .done(),
        .start_pass(shared_pkg::start_pass), .pass_done(),
        .ofmap_dump(), .dump_done(1'b0),
        .words_num(),
        .start_forward(), .transfer_type(),
        .re_from_dram(), .rdata_from_dram(), .valid_from_dram(),
        .start_backward(), .we_to_dram(), .wdata_to_dram(), .transfer_done(),
        .filter_ids(), .filter_channel_ids(),
        .ifmap_ids(), .ifmap_channel_ids(),
        .psum_ids(), .psum_channel_ids()
    );

    // ========================================================================
    // GLB backdoor write helpers
    // ========================================================================
    task write_glb(input int glb_t, input int addr, input [15:0] val);
        int sub; sub = addr >> 2;
        case (glb_t)
            0: case (addr & 3)
                0: DUT.GLB.U1_IFMAP.U0_0.mem[sub] = val;
                1: DUT.GLB.U1_IFMAP.U0_1.mem[sub] = val;
                2: DUT.GLB.U1_IFMAP.U1_0.mem[sub] = val;
                3: DUT.GLB.U1_IFMAP.U1_1.mem[sub] = val;
            endcase
            1: case (addr & 3)
                0: DUT.GLB.U2_FILTER.U0_0.mem[sub] = val;
                1: DUT.GLB.U2_FILTER.U0_1.mem[sub] = val;
                2: DUT.GLB.U2_FILTER.U1_0.mem[sub] = val;
                3: DUT.GLB.U2_FILTER.U1_1.mem[sub] = val;
            endcase
            2: case (addr & 3)
                0: DUT.GLB.U3_BIAS.U0_0.mem[sub] = val;
                1: DUT.GLB.U3_BIAS.U0_1.mem[sub] = val;
                2: DUT.GLB.U3_BIAS.U1_0.mem[sub] = val;
                3: DUT.GLB.U3_BIAS.U1_1.mem[sub] = val;
            endcase
        endcase
    endtask

    // ========================================================================
    // Main
    // ========================================================================
    integer i;

    initial begin
        $display("=== tb_debug_v2 ===");

        // Reset
        reset_n = 0;
        repeat(20) @(posedge core_clk);
        reset_n = 1;
        repeat(10) @(posedge core_clk);

        // Step 1: Backdoor GLB data (tiny test)
        $display("[%0t] Loading GLB data...", $time);
        for (i = 0; i < 64; i = i + 1) write_glb(0, i, (i + 1) * 256);
        write_glb(1, 0, 16'h0100); write_glb(1, 1, 0); write_glb(1, 2, 0);
        write_glb(1, 3, 0); write_glb(1, 4, 16'h0200); write_glb(1, 5, 0);
        write_glb(1, 6, 0); write_glb(1, 7, 0); write_glb(1, 8, 16'h0100);
        write_glb(2, 0, 0);
        $display("[%0t] GLB data loaded.", $time);

        // Step 2: Scan chain (tiny config, 3644 bits)
        $display("[%0t] Loading scan chain...", $time);
        cfg_scan_chain("H:/moateff_trace/debug_campaign/tiny_config_lf.txt");
        $display("[%0t] Scan chain loaded.", $time);

        // Step 3: Start scheduler
        $display("[%0t] Sending start...", $time);
        start = 1;
        @(posedge core_clk);
        start = 0;
        $display("[%0t] Start pulse done.", $time);

        // Step 3b: Pulse start_pass to trigger pass
        @(posedge core_clk);
        shared_pkg::start_pass = 1;
        @(posedge core_clk);
        shared_pkg::start_pass = 0;
        $display("[%0t] start_pass pulsed.", $time);

        // Step 4: Monitor until done
        for (i = 0; i < 5000; i = i + 1) begin
            @(posedge core_clk);
            if (i % 500 == 0 || DUT.SCHEDULER.state_crnt != 0) begin
                $display("[%0t] C=%0d SchSt=%0d PassSt=%0d start_noc=%b nocDone=%b busy=%b done=%b",
                    $time, i, DUT.SCHEDULER.state_crnt,
                    DUT.PROCESSING.nocs_top_inst.pass_controller_inst.state_crnt,
                    DUT.SCHEDULER.start_noc,
                    DUT.PROCESSING.nocs_top_inst.pass_controller_inst.done,
                    DUT.SCHEDULER.busy, DUT.SCHEDULER.done);
            end
            if (DUT.SCHEDULER.done) begin
                $display("[%0t] DONE!", $time);
                i = 9999;
            end
        end

        $display("[%0t] === Final State ===", $time);
        $display("Scheduler state=%0d", DUT.SCHEDULER.state_crnt);
        $display("PassCtrl state=%0d", DUT.PROCESSING.nocs_top_inst.pass_controller_inst.state_crnt);
        $display("Sch start_noc=%b, Pass done=%b", DUT.SCHEDULER.start_noc,
            DUT.PROCESSING.nocs_top_inst.pass_controller_inst.done);
        $display("Ifmap done=%b Filter done=%b Ipsum done=%b Opsum done=%b",
            DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ifmap_noc_inst.done,
            DUT.PROCESSING.nocs_top_inst.noc_controller_inst.filter_noc_inst.done,
            DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ipsum_noc_inst.done,
            DUT.PROCESSING.nocs_top_inst.noc_controller_inst.opsum_noc_inst.done);
        $stop;
    end

endmodule
