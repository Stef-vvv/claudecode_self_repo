// ===========================================================================
// tb_debug_step1.sv — Step 1: GLB backdoor write/read verification
// ===========================================================================
// Goal: Verify GLB can be written via backdoor and read via NoC port correctly.
// If this fails, nothing downstream can work.
// ===========================================================================
`timescale 1ns / 1ps

module tb_debug_step1;

    localparam CORE_CLK_PERIOD = 10;   // 100 MHz
    localparam LINK_CLK_PERIOD = 30;   // ~33 MHz

    reg core_clk = 0;
    reg link_clk = 0;
    reg reset_n = 0;
    reg start = 0;
    wire scan_en_dut, scan_in_dut, scan_out_dut;
    assign scan_en_dut = shared_pkg::scan_en;
    assign scan_in_dut = shared_pkg::scan_in;

    wire scan_out;
    wire busy, done;

    // DUT signals (DRAM side)
    wire re_from_dram;
    wire [63:0] rdata_from_dram;
    wire valid_from_dram;
    wire start_forward;
    wire start_backward;
    wire [1:0] transfer_type;

    import shared_pkg::*;
    import cfg_pkg::*;

    // Instantiate full eyeriss
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
        .scan_en(scan_en_dut), .scan_in(scan_in_dut), .scan_out(scan_out_dut),
        .start(start),
        .busy(busy), .done(done),
        .start_pass(1'b0), .pass_done(), .ofmap_dump(), .dump_done(1'b0),
        .words_num(0), .start_forward(start_forward), .transfer_type(transfer_type),
        .re_from_dram(re_from_dram), .rdata_from_dram(rdata_from_dram),
        .valid_from_dram(valid_from_dram),
        .start_backward(start_backward), .we_to_dram(), .wdata_to_dram(),
        .transfer_done(),
        .filter_ids(), .filter_channel_ids(),
        .ifmap_ids(), .ifmap_channel_ids(),
        .psum_ids(), .psum_channel_ids()
    );

    // Clocks
    always #(CORE_CLK_PERIOD/2) core_clk = ~core_clk;
    always #(LINK_CLK_PERIOD/2) link_clk = ~link_clk;

    // ========================================================================
    // Load tiny config via scan chain
    // ========================================================================
    task load_scan_chain(input string cfg_file);
        int fd, i, bits;
        reg [7:0] char_buf [0:20000];  // buffer for file contents
        begin
            // Read entire file as binary bytes
            fd = $fopen(cfg_file, "rb");
            if (fd == 0) begin
                $display("[FAIL] Cannot open config: %s", cfg_file);
                $stop;
            end
            bits = 0;
            while (!$feof(fd)) begin
                char_buf[bits] = $fgetc(fd);
                if (char_buf[bits] == "0" || char_buf[bits] == "1")
                    bits = bits + 1;
            end
            $fclose(fd);

            $display("[INFO] Scan chain: %0d bits from %s", bits, cfg_file);

            // Shift in bits (same order as read)
            scan_en = 1;
            for (i = 0; i < bits; i = i + 1) begin
                scan_in = (char_buf[i] == "1");
                #(CORE_CLK_PERIOD);
            end
            scan_en = 0;
            #(CORE_CLK_PERIOD * 5);
            $display("[INFO] Scan chain loaded (%0d bits)", bits);
        end
    endtask

    // ========================================================================
    // Backdoor GLB write (direct hierarchical access to dual_bram mem)
    // ========================================================================
    task backdoor_write_ifmap_glb(input int addr, input [15:0] data);
        int sub;
        begin
            // GLB 4-bank: addr[1:0]=bank, addr>>2=sub-address
            sub = addr >> 2;
            case (addr & 2'b11)
                2'b00: DUT.GLB.U1_IFMAP.U0_0.mem[sub] = data;
                2'b01: DUT.GLB.U1_IFMAP.U0_1.mem[sub] = data;
                2'b10: DUT.GLB.U1_IFMAP.U1_0.mem[sub] = data;
                2'b11: DUT.GLB.U1_IFMAP.U1_1.mem[sub] = data;
            endcase
        end
    endtask

    task backdoor_write_filter_glb(input int addr, input [15:0] data);
        int sub;
        begin
            sub = addr >> 2;
            case (addr & 2'b11)
                2'b00: DUT.GLB.U2_FILTER.U0_0.mem[sub] = data;
                2'b01: DUT.GLB.U2_FILTER.U0_1.mem[sub] = data;
                2'b10: DUT.GLB.U2_FILTER.U1_0.mem[sub] = data;
                2'b11: DUT.GLB.U2_FILTER.U1_1.mem[sub] = data;
            endcase
        end
    endtask

    task backdoor_write_bias_glb(input int addr, input [15:0] data);
        int sub;
        begin
            sub = addr >> 2;
            case (addr & 2'b11)
                2'b00: DUT.GLB.U3_BIAS.U0_0.mem[sub] = data;
                2'b01: DUT.GLB.U3_BIAS.U0_1.mem[sub] = data;
                2'b10: DUT.GLB.U3_BIAS.U1_0.mem[sub] = data;
                2'b11: DUT.GLB.U3_BIAS.U1_1.mem[sub] = data;
            endcase
        end
    endtask

    // ========================================================================
    // Monitor: probe internal FSM states
    // ========================================================================
    task monitor_internals;
        begin
            $display("\n=== Internal State Monitor @ %0t ===", $time);

            // Scheduler state (enum: IDLE=0, CHECK=1, OUTER_LOOP=2, INNER_LOOP=3,
            //                    START_PASS=4, PROCESS=5, PASS_DONE=6, DUMPING=7, DONE=8)
            $display("Scheduler: state=%0d, M_crnt=%0d, C_crnt=%0d, N_crnt=%0d, E_crnt=%0d, m_crnt=%0d",
                DUT.SCHEDULER.state_crnt, DUT.SCHEDULER.M_crnt, DUT.SCHEDULER.C_crnt,
                DUT.SCHEDULER.N_crnt, DUT.SCHEDULER.E_crnt, DUT.SCHEDULER.m_crnt);

            // Pass controller state (enum: IDLE=0, START_NOCS=1, PROCESSING=2, DONE=3)
            $display("PassCtrl: state=%0d",
                DUT.PROCESSING.nocs_top_inst.pass_controller_inst.state_crnt);

            // NoC channel done signals
            $display("NoC done: ifmap=%b filter=%b ipsum=%b opsum=%b",
                DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ifmap_noc_inst.done,
                DUT.PROCESSING.nocs_top_inst.noc_controller_inst.filter_noc_inst.done,
                DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ipsum_noc_inst.done,
                DUT.PROCESSING.nocs_top_inst.noc_controller_inst.opsum_noc_inst.done);

            $display("=== End Monitor ===\n");
        end
    endtask

    // ========================================================================
    // Main test
    // ========================================================================
    integer cycle;
    reg [15:0] test_val;
    reg [15:0] read_val;

    initial begin
        $display("========================================");
        $display(" STEP 1: GLB Backdoor Write/Read Test");
        $display("========================================");

        // Reset
        reset_n = 0;
        repeat(10) @(posedge core_clk);
        reset_n = 1;
        repeat(10) @(posedge core_clk);

        // Test 1: Write and verify ifmap GLB
        $display("\n--- Test 1: IFMAP GLB write/read ---");
        for (int a = 0; a < 64; a = a + 1) begin
            test_val = 16'h1000 + a;
            backdoor_write_ifmap_glb(a, test_val);
        end
        $display("Wrote 64 test values to IFMAP GLB");

        // Test 2: Write filter GLB
        $display("\n--- Test 2: FILTER GLB write/read ---");
        for (int a = 0; a < 9; a = a + 1) begin
            test_val = 16'h0200 + a;
            backdoor_write_filter_glb(a, test_val);
        end
        $display("Wrote 9 test values to FILTER GLB");

        // Test 3: Load scan chain using original cfg_pkg task
        $display("\n--- Test 3: Load scan chain ---");
        wait_core_cycle(5);
        cfg_scan_chain("H:/moateff_trace/debug_campaign/tiny_config_lf.txt");
        $display("[INFO] Scan chain loaded");

        // Test 4: Start scheduler + pulse start_pass
        $display("\n--- Test 4: Start scheduler ---");
        start = 1;
        @(posedge core_clk);
        start = 0;
        repeat(5) @(posedge core_clk);
        // Pulse start_pass to trigger pass execution
        $display("[INFO] Pulsing start_pass");
        force DUT.start_pass = 1;
        @(posedge core_clk);
        force DUT.start_pass = 0;
        release DUT.start_pass;
        $display("[INFO] start_pass pulsed");

        // Monitor for 200 cycles
        $display("\n--- Monitoring ---");
        cycle = 0;
        while (cycle < 200) begin
            @(posedge core_clk);
            cycle = cycle + 1;
            if (cycle % 50 == 0) begin
                $display("[%0d] start=%b busy=%b done=%b", cycle, start, busy, done);
            end
            if (done) begin
                $display("[%0d] DONE!", cycle);
                monitor_internals;
                $stop;
            end
        end

        $display("\n[INFO] 200 cycles elapsed, no done. Checking internals:");
        monitor_internals;

        $display("\n=== Step 1 complete ===");
        $stop;
    end

endmodule
