// ===========================================================================
// tb_debug_v5.sv — Force correct parameters, bypass scan chain bit-order bug
// ===========================================================================
`timescale 1ns / 1ps

import shared_pkg::*;
import cfg_pkg::*;

module tb_debug_v5;

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

    `define SCHED DUT.SCHEDULER
    `define PASSCTRL DUT.PROCESSING.nocs_top_inst.pass_controller_inst
    `define INOC DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ifmap_noc_inst
    `define FNOC DUT.PROCESSING.nocs_top_inst.noc_controller_inst.filter_noc_inst
    `define ISNOC DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ipsum_noc_inst
    `define OSNOC DUT.PROCESSING.nocs_top_inst.noc_controller_inst.opsum_noc_inst

    // Force correct tiny config parameters
    task force_correct_params;
        begin
            // Scheduler params (correct from scan chain)
            // E=6, C=1, M=1, N=1, m=1, n=1 are already correct
            // Fix the broken ones: e, p, q, r, t
            force `SCHED.e = 8'd6;
            force `SCHED.p = 5'd1;
            force `SCHED.q = 3'd1;
            force `SCHED.r = 2'd1;
            force `SCHED.t = 3'd1;

            // Also fix scan chain outputs (they feed processing_unit)
            force DUT.SCAN_CHAIN.e = 8'd6;
            force DUT.SCAN_CHAIN.p = 5'd1;
            force DUT.SCAN_CHAIN.q = 3'd1;
            force DUT.SCAN_CHAIN.r = 2'd1;
            force DUT.SCAN_CHAIN.t = 3'd1;

            $display("[INFO] Parameters forced: e=6 p=1 q=1 r=1 t=1");
        end
    endtask

    // GLB backdoor
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

    task probe;
        begin
            $display("\n[T=%0t] ==========", $time);
            $display("Sched: state=%0d start_noc=%b busy=%b", `SCHED.state_crnt, `SCHED.start_noc, `SCHED.busy);
            $display("PassCtrl: state=%0d", `PASSCTRL.state_crnt);
            $display("Ifmap: done=%b we=%b full=%b re=%b addr=%0d tag=(%0d,%0d)",
                `INOC.done, `INOC.we_to_gin_fifo, `INOC.gin_fifo_full,
                `INOC.re_from_glb, `INOC.addr, `INOC.row_tag, `INOC.col_tag);
            $display("Filter: done=%b we=%b full=%b re=%b addr=%0d tag=(%0d,%0d)",
                `FNOC.done, `FNOC.we_to_gin_fifo, `FNOC.gin_fifo_full,
                `FNOC.re_from_glb, `FNOC.addr, `FNOC.row_tag, `FNOC.col_tag);
            $display("Ipsum: done=%b Opsum: done=%b", `ISNOC.done, `OSNOC.done);
        end
    endtask

    integer i;

    initial begin
        $display("=== tb_debug_v5: Force-corrected parameters ===");

        reset_n = 0; repeat(20) @(posedge core_clk);
        reset_n = 1; repeat(10) @(posedge core_clk);

        // Load GLB data (tiny test: 8x8 ifmap values 1..64)
        for (i = 0; i < 64; i = i + 1) write_glb(0, i, (i + 1) * 256);
        write_glb(1,0,16'h0100); write_glb(1,1,0); write_glb(1,2,0);
        write_glb(1,3,0); write_glb(1,4,16'h0200); write_glb(1,5,0);
        write_glb(1,6,0); write_glb(1,7,0); write_glb(1,8,16'h0100);
        write_glb(2,0,0);
        $display("[%0t] GLB data loaded", $time);

        // Load scan chain (for the correct params + PE config)
        cfg_scan_chain("H:/moateff_trace/debug_campaign/tiny_config_lf.txt");
        repeat(20) @(posedge core_clk); // Wait for parameter pipeline
        $display("[%0t] Scan chain loaded", $time);

        // Force correct parameters (fixes scan chain bit-order bug)
        force_correct_params;

        // Start + start_pass
        start = 1; @(posedge core_clk); start = 0;
        @(posedge core_clk);
        shared_pkg::start_pass = 1;
        @(posedge core_clk);
        shared_pkg::start_pass = 0;
        $display("[%0t] start + start_pass pulsed", $time);

        // Monitor
        for (i = 0; i < 500; i = i + 1) begin
            @(posedge core_clk);
            if (i == 0 || i == 1 || i == 2 || i == 5 || i == 10 ||
                i % 50 == 0 || `SCHED.done || `PASSCTRL.done)
                probe;

            if (`SCHED.done) begin
                $display("\n*** DONE at cycle %0d ***", i);
                i = 9999;
            end
        end

        probe;
        $display("\n=== v5 complete ===");
        $stop;
    end

endmodule
