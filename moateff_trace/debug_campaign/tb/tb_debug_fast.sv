// ===========================================================================
// tb_debug_fast.sv — Minimal debug: skip scan chain, force params, watch FSM
// ===========================================================================
`timescale 1ns / 1ps

import shared_pkg::*;

module tb_debug_fast;

    localparam CORE_CLK_PERIOD = 10;
    localparam LINK_CLK_PERIOD = 30;

    reg core_clk = 0;
    reg link_clk = 0;
    reg reset_n = 0;
    reg start = 0;

    always #(CORE_CLK_PERIOD/2) core_clk = ~core_clk;
    always #(LINK_CLK_PERIOD/2) link_clk = ~link_clk;

    // DUT signals
    wire scan_out_w;
    wire busy, done;
    wire start_forward_w, start_backward_w;
    wire re_from_dram_w, valid_from_dram_w, we_to_dram_w;
    wire [63:0] rdata_from_dram_w, wdata_to_dram_w;
    wire [1:0] transfer_type_w;
    wire [ADDR_WIDTH-1:0] words_num_w;

    assign shared_pkg::re_from_dram = 0;
    assign shared_pkg::rdata_from_dram = 0;
    assign shared_pkg::valid_from_dram = 0;
    assign shared_pkg::start_backward = 0;

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
        .core_clk(core_clk), .link_clk(link_clk),
        .reset(~reset_n),
        .scan_en(shared_pkg::scan_en), .scan_in(shared_pkg::scan_in),
        .scan_out(scan_out_w),
        .start(start), .busy(busy), .done(done),
        .start_pass(shared_pkg::start_pass), .pass_done(),
        .ofmap_dump(), .dump_done(1'b0),
        .words_num(words_num_w),
        .start_forward(start_forward_w), .transfer_type(transfer_type_w),
        .re_from_dram(re_from_dram_w), .rdata_from_dram(rdata_from_dram_w),
        .valid_from_dram(valid_from_dram_w),
        .start_backward(start_backward_w), .we_to_dram(we_to_dram_w),
        .wdata_to_dram(wdata_to_dram_w), .transfer_done(),
        .filter_ids(), .filter_channel_ids(),
        .ifmap_ids(), .ifmap_channel_ids(),
        .psum_ids(), .psum_channel_ids()
    );

    // ========================================================================
    // Force scheduler parameters directly (skip scan chain)
    // ========================================================================
    task force_params;
        begin
            // Tiny test: 8x8x1, 3x3 filter, 6x6 ofmap, stride=1
            force DUT.SCHEDULER.parameter_H = 8'd8;
            force DUT.SCHEDULER.parameter_W = 8'd8;
            force DUT.SCHEDULER.parameter_R = 4'd3;
            force DUT.SCHEDULER.parameter_S = 4'd3;
            force DUT.SCHEDULER.parameter_E = 6'd6;
            force DUT.SCHEDULER.parameter_F = 6'd6;
            force DUT.SCHEDULER.parameter_C = 10'd1;
            force DUT.SCHEDULER.parameter_M = 10'd1;
            force DUT.SCHEDULER.parameter_N = 3'd1;
            force DUT.SCHEDULER.parameter_U = 3'd1;
            force DUT.SCHEDULER.parameter_m = 8'd1;
            force DUT.SCHEDULER.parameter_n = 3'd1;
            force DUT.SCHEDULER.parameter_e = 8'd6;
            force DUT.SCHEDULER.parameter_p = 5'd1;
            force DUT.SCHEDULER.parameter_q = 3'd1;
            force DUT.SCHEDULER.parameter_r = 2'd1;
            force DUT.SCHEDULER.parameter_t = 3'd1;
            $display("[INFO] Scheduler parameters forced (tiny test: 8x8x1, K=3x3)");
        end
    endtask

    // ========================================================================
    // GLB backdoor write
    // ========================================================================
    task backdoor_write_glb_16(input int glb_type, input int addr, input [15:0] data);
        int sub;
        begin
            sub = addr >> 2;
            case (glb_type)
                0: case (addr & 2'b11)
                    2'b00: DUT.GLB.U1_IFMAP.U0_0.mem[sub] = data;
                    2'b01: DUT.GLB.U1_IFMAP.U0_1.mem[sub] = data;
                    2'b10: DUT.GLB.U1_IFMAP.U1_0.mem[sub] = data;
                    2'b11: DUT.GLB.U1_IFMAP.U1_1.mem[sub] = data;
                endcase
                1: case (addr & 2'b11)
                    2'b00: DUT.GLB.U2_FILTER.U0_0.mem[sub] = data;
                    2'b01: DUT.GLB.U2_FILTER.U0_1.mem[sub] = data;
                    2'b10: DUT.GLB.U2_FILTER.U1_0.mem[sub] = data;
                    2'b11: DUT.GLB.U2_FILTER.U1_1.mem[sub] = data;
                endcase
                2: case (addr & 2'b11)
                    2'b00: DUT.GLB.U3_BIAS.U0_0.mem[sub] = data;
                    2'b01: DUT.GLB.U3_BIAS.U0_1.mem[sub] = data;
                    2'b10: DUT.GLB.U3_BIAS.U1_0.mem[sub] = data;
                    2'b11: DUT.GLB.U3_BIAS.U1_1.mem[sub] = data;
                endcase
            endcase
        end
    endtask

    // ========================================================================
    // Monitor
    // ========================================================================
    task monitor;
        begin
            $display("\n[T=%0t] ==============", $time);
            $display("Top:    start=%b busy=%b done=%b", start, busy, done);
            $display("Scheduler: state=%0d, M=%0d C=%0d N=%0d E=%0d m=%0d",
                DUT.SCHEDULER.state_crnt, DUT.SCHEDULER.M_crnt, DUT.SCHEDULER.C_crnt,
                DUT.SCHEDULER.N_crnt, DUT.SCHEDULER.E_crnt, DUT.SCHEDULER.m_crnt);
            $display("PassCtrl: state=%0d",
                DUT.PROCESSING.nocs_top_inst.pass_controller_inst.state_crnt);
            $display("NoC done: I=%b F=%b IS=%b OS=%b",
                DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ifmap_noc_inst.done,
                DUT.PROCESSING.nocs_top_inst.noc_controller_inst.filter_noc_inst.done,
                DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ipsum_noc_inst.done,
                DUT.PROCESSING.nocs_top_inst.noc_controller_inst.opsum_noc_inst.done);
        end
    endtask

    // ========================================================================
    // Main
    // ========================================================================
    integer cycle;

    initial begin
        $display("=== tb_debug_fast ===");

        // Reset
        reset_n = 0; shared_pkg::scan_en = 0; shared_pkg::scan_in = 0;
        repeat(20) @(posedge core_clk);
        reset_n = 1;
        repeat(10) @(posedge core_clk);

        // Force parameters
        force_params;

        // Backdoor: write tiny test data
        // Ifmap (8x8 = 64 values, addr 0-63): values 1..64 in Q3.13
        $display("\n[INFO] Loading ifmap data...");
        for (int a = 0; a < 64; a = a + 1)
            backdoor_write_glb_16(0, a, (a + 1) * 256);  // value*256 = Q3.13

        // Filter (3x3 = 9 values): simple pattern [1,0,0; 0,2,0; 0,0,1]
        $display("[INFO] Loading filter data...");
        backdoor_write_glb_16(1, 0, 16'h0100); // 1*256
        backdoor_write_glb_16(1, 1, 0);
        backdoor_write_glb_16(1, 2, 0);
        backdoor_write_glb_16(1, 3, 0);
        backdoor_write_glb_16(1, 4, 16'h0200); // 2*256
        backdoor_write_glb_16(1, 5, 0);
        backdoor_write_glb_16(1, 6, 0);
        backdoor_write_glb_16(1, 7, 0);
        backdoor_write_glb_16(1, 8, 16'h0100); // 1*256

        // Bias = 0
        $display("[INFO] Loading bias...");
        backdoor_write_glb_16(2, 0, 0);

        $display("[INFO] Data loaded, starting scheduler...");

        // Start
        start = 1;
        @(posedge core_clk);
        start = 0;
        repeat(5) @(posedge core_clk);

        // Pulse start_pass
        force DUT.SCHEDULER.start_pass = 1;
        @(posedge core_clk);
        force DUT.SCHEDULER.start_pass = 0;
        release DUT.SCHEDULER.start_pass;
        $display("[INFO] start_pass pulsed");

        // Monitor loop
        cycle = 0;
        while (cycle < 500 && !done) begin
            @(posedge core_clk);
            cycle = cycle + 1;

            if (cycle == 1 || cycle % 100 == 0 || done)
                monitor;

            if (cycle == 1) begin
                // Extra detail at start
                $display("Scheduler start_noc=%b", DUT.SCHEDULER.start_noc);
                $display("PassCtrl start=%b", DUT.PROCESSING.nocs_top_inst.pass_controller_inst.start);
            end
        end

        if (done)
            $display("\n*** DONE at cycle %0d ***", cycle);
        else
            $display("\n*** TIMEOUT at cycle %0d ***", cycle);

        monitor;
        $stop;
    end

endmodule
