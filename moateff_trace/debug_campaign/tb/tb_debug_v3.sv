// ===========================================================================
// tb_debug_v3.sv — Deep NoC probe: check index generators, mappers, tags
// ===========================================================================
`timescale 1ns / 1ps

import shared_pkg::*;
import cfg_pkg::*;

module tb_debug_v3;

    localparam CORE_CLK_PERIOD = 10;
    localparam LINK_CLK_PERIOD = 30;

    reg core_clk = 0;
    reg link_clk = 0;
    reg reset_n = 0;
    reg start = 0;

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
        .DATA_WIDTH_IFMAP(16), .ROW_TAG_WIDTH_IFMAP(4), .COL_TAG_WIDTH_IFMAP(5),
        .DATA_WIDTH_FILTER(64), .ROW_TAG_WIDTH_FILTER(4), .COL_TAG_WIDTH_FILTER(4),
        .DATA_WIDTH_PSUM(64), .ROW_TAG_WIDTH_PSUM(4), .COL_TAG_WIDTH_PSUM(4),
        .NUM_OF_ROWS(12), .NUM_OF_COLS(14),
        .GIN_FIFO_DEPTH(16), .GON_FIFO_DEPTH(16),
        .IFMAP_FIFO_DEPTH(4), .FILTER_FIFO_DEPTH(8), .PSUM_FIFO_DEPTH(8),
        .IFMAP_SPAD_DEPTH(12), .FILTER_SPAD_DEPTH(224), .PSUM_SPAD_DEPTH(24),
        .H_WIDTH(8), .W_WIDTH(8), .R_WIDTH(4), .S_WIDTH(4),
        .E_WIDTH(6), .F_WIDTH(6), .C_WIDTH(10), .M_WIDTH(10),
        .N_WIDTH(3), .U_WIDTH(3),
        .m_WIDTH(8), .n_WIDTH(3), .e_WIDTH(8),
        .p_WIDTH(5), .q_WIDTH(3), .r_WIDTH(2), .t_WIDTH(3),
        .ROW_MAJOR(1), .ADDR_WIDTH(20), .DATA_WIDTH(16),
        .FIFO_WIDTH(64), .FIFO_DEPTH(8),
        .IFMAP_GLB_DEPTH(7945), .FILTER_GLB_DEPTH(3872),
        .PSUM_GLB_DEPTH(46656), .BIAS_GLB_DEPTH(64)
    ) DUT (
        .core_clk, .link_clk, .reset(~reset_n),
        .scan_en(shared_pkg::scan_en), .scan_in(shared_pkg::scan_in), .scan_out(),
        .start(start), .busy(), .done(),
        .start_pass(shared_pkg::start_pass), .pass_done(),
        .ofmap_dump(), .dump_done(1'b0),
        .words_num(), .start_forward(), .transfer_type(),
        .re_from_dram(), .rdata_from_dram(), .valid_from_dram(),
        .start_backward(), .we_to_dram(), .wdata_to_dram(), .transfer_done(),
        .filter_ids(), .filter_channel_ids(),
        .ifmap_ids(), .ifmap_channel_ids(),
        .psum_ids(), .psum_channel_ids()
    );

    // Shortcuts for hierarchy
    `define IFMAP_NOC   DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ifmap_noc_inst
    `define FILTER_NOC  DUT.PROCESSING.nocs_top_inst.noc_controller_inst.filter_noc_inst
    `define IPSUM_NOC   DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ipsum_noc_inst
    `define OPSUM_NOC   DUT.PROCESSING.nocs_top_inst.noc_controller_inst.opsum_noc_inst
    `define PASSCTRL    DUT.PROCESSING.nocs_top_inst.pass_controller_inst
    `define SCHED       DUT.SCHEDULER

    // ========================================================================
    // GLB backdoor
    // ========================================================================
    task write_glb(input int t, input int a, input [15:0] v);
        int s; s = a >> 2;
        case (t)
            0: case (a & 3)
                0: DUT.GLB.U1_IFMAP.U0_0.mem[s] = v;
                1: DUT.GLB.U1_IFMAP.U0_1.mem[s] = v;
                2: DUT.GLB.U1_IFMAP.U1_0.mem[s] = v;
                3: DUT.GLB.U1_IFMAP.U1_1.mem[s] = v;
            endcase
            1: case (a & 3)
                0: DUT.GLB.U2_FILTER.U0_0.mem[s] = v;
                1: DUT.GLB.U2_FILTER.U0_1.mem[s] = v;
                2: DUT.GLB.U2_FILTER.U1_0.mem[s] = v;
                3: DUT.GLB.U2_FILTER.U1_1.mem[s] = v;
            endcase
            2: case (a & 3)
                0: DUT.GLB.U3_BIAS.U0_0.mem[s] = v;
                1: DUT.GLB.U3_BIAS.U0_1.mem[s] = v;
                2: DUT.GLB.U3_BIAS.U1_0.mem[s] = v;
                3: DUT.GLB.U3_BIAS.U1_1.mem[s] = v;
            endcase
        endcase
    endtask

    // ========================================================================
    // Deep NoC probe
    // ========================================================================
    task probe_noc;
        begin
            $display("\n=== NoC Deep Probe @ %0t ===", $time);

            // Scheduler
            $display("[Scheduler] state=%0d start_noc=%b busy=%b",
                `SCHED.state_crnt, `SCHED.start_noc, `SCHED.busy);
            $display("  M_crnt=%0d C_crnt=%0d E_crnt=%0d m_crnt=%0d N_crnt=%0d",
                `SCHED.M_crnt, `SCHED.C_crnt, `SCHED.E_crnt, `SCHED.m_crnt, `SCHED.N_crnt);

            // Pass controller
            $display("[PassCtrl] state=%0d done=%b",
                `PASSCTRL.state_crnt, `PASSCTRL.done);

            // Ifmap NoC: accessible signals
            $display("[IfmapNoC] done=%b we=%b gin_full=%b re=%b addr=%0d",
                `IFMAP_NOC.done, `IFMAP_NOC.we_to_gin_fifo,
                `IFMAP_NOC.gin_fifo_full, `IFMAP_NOC.re_from_glb,
                `IFMAP_NOC.addr);
            $display("  tag: row=%0d col=%0d",
                `IFMAP_NOC.row_tag, `IFMAP_NOC.col_tag);

            // Filter NoC
            $display("[FilterNoC] done=%b we=%b gin_full=%b re=%b addr=%0d",
                `FILTER_NOC.done, `FILTER_NOC.we_to_gin_fifo,
                `FILTER_NOC.gin_fifo_full, `FILTER_NOC.re_from_glb,
                `FILTER_NOC.addr);
            $display("  tag: row=%0d col=%0d",
                `FILTER_NOC.row_tag, `FILTER_NOC.col_tag);

            // Ipsum NoC
            $display("[IpsumNoC] done=%b we=%b gin_full=%b re=%b",
                `IPSUM_NOC.done, `IPSUM_NOC.we_to_gin_fifo,
                `IPSUM_NOC.gin_fifo_full, `IPSUM_NOC.re_from_glb);

            // Opsum NoC (output direction — no gin_fifo ports)
            $display("[OpsumNoC] done=%b", `OPSUM_NOC.done);

            $display("=== End Probe ===\n");
        end
    endtask

    // ========================================================================
    // Main
    // ========================================================================
    integer i;

    initial begin
        $display("=== tb_debug_v3: Deep NoC Probe ===");

        // Reset
        reset_n = 0;
        repeat(20) @(posedge core_clk);
        reset_n = 1;
        repeat(10) @(posedge core_clk);

        // Load GLB data
        for (i = 0; i < 64; i = i + 1) write_glb(0, i, (i + 1) * 256);
        write_glb(1,0,16'h0100); write_glb(1,1,0); write_glb(1,2,0);
        write_glb(1,3,0); write_glb(1,4,16'h0200); write_glb(1,5,0);
        write_glb(1,6,0); write_glb(1,7,0); write_glb(1,8,16'h0100);
        write_glb(2, 0, 0);
        $display("[%0t] GLB data loaded", $time);

        // Load scan chain
        cfg_scan_chain("H:/moateff_trace/debug_campaign/tiny_config_lf.txt");
        $display("[%0t] Scan chain loaded", $time);

        // Start
        start = 1;
        @(posedge core_clk);
        start = 0;

        // Pulse start_pass
        @(posedge core_clk);
        shared_pkg::start_pass = 1;
        @(posedge core_clk);
        shared_pkg::start_pass = 0;
        $display("[%0t] start_pass pulsed", $time);

        // Probe every 50 cycles for first 500 cycles
        for (i = 0; i < 500; i = i + 1) begin
            @(posedge core_clk);
            if (i == 0 || i == 1 || i == 2 || i == 5 || i == 10 ||
                i % 100 == 0 || `SCHED.done)
                probe_noc;
        end

        probe_noc;
        $display("\n*** Debug v3 complete ***");
        $stop;
    end

endmodule
