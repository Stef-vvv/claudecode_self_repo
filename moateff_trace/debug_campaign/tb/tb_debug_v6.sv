// ===========================================================================
// tb_debug_v6.sv — Verify parameter propagation + force at NoC level
// ===========================================================================
`timescale 1ns / 1ps
import shared_pkg::*;
import cfg_pkg::*;

module tb_debug_v6;
    localparam CORE_CLK_PERIOD = 10;
    localparam LINK_CLK_PERIOD = 30;
    reg core_clk=0, link_clk=0, reset_n=0, start=0;
    always #(CORE_CLK_PERIOD/2) core_clk = ~core_clk;
    always #(LINK_CLK_PERIOD/2) link_clk = ~link_clk;
    assign shared_pkg::core_clk=core_clk; assign shared_pkg::link_clk=link_clk;
    assign shared_pkg::re_from_dram=0; assign shared_pkg::rdata_from_dram=0;
    assign shared_pkg::valid_from_dram=0; assign shared_pkg::start_backward=0;
    assign shared_pkg::words_num=0; assign shared_pkg::start_forward=0;
    assign shared_pkg::transfer_type=0;

    eyeriss #(.DATA_WIDTH_IFMAP(16),.ROW_TAG_WIDTH_IFMAP(4),.COL_TAG_WIDTH_IFMAP(5),
        .DATA_WIDTH_FILTER(64),.ROW_TAG_WIDTH_FILTER(4),.COL_TAG_WIDTH_FILTER(4),
        .DATA_WIDTH_PSUM(64),.ROW_TAG_WIDTH_PSUM(4),.COL_TAG_WIDTH_PSUM(4),
        .NUM_OF_ROWS(12),.NUM_OF_COLS(14),.GIN_FIFO_DEPTH(16),.GON_FIFO_DEPTH(16),
        .IFMAP_FIFO_DEPTH(4),.FILTER_FIFO_DEPTH(8),.PSUM_FIFO_DEPTH(8),
        .IFMAP_SPAD_DEPTH(12),.FILTER_SPAD_DEPTH(224),.PSUM_SPAD_DEPTH(24),
        .H_WIDTH(8),.W_WIDTH(8),.R_WIDTH(4),.S_WIDTH(4),.E_WIDTH(6),.F_WIDTH(6),
        .C_WIDTH(10),.M_WIDTH(10),.N_WIDTH(3),.U_WIDTH(3),
        .m_WIDTH(8),.n_WIDTH(3),.e_WIDTH(8),.p_WIDTH(5),.q_WIDTH(3),.r_WIDTH(2),.t_WIDTH(3),
        .ROW_MAJOR(1),.ADDR_WIDTH(20),.DATA_WIDTH(16),.FIFO_WIDTH(64),.FIFO_DEPTH(8),
        .IFMAP_GLB_DEPTH(7945),.FILTER_GLB_DEPTH(3872),
        .PSUM_GLB_DEPTH(46656),.BIAS_GLB_DEPTH(64)
    ) DUT (.core_clk,.link_clk,.reset(~reset_n),
        .scan_en(shared_pkg::scan_en),.scan_in(shared_pkg::scan_in),.scan_out(),
        .start(start),.busy(),.done(),
        .start_pass(shared_pkg::start_pass),.pass_done(),
        .ofmap_dump(),.dump_done(1'b0),
        .words_num(),.start_forward(),.transfer_type(),
        .re_from_dram(),.rdata_from_dram(),.valid_from_dram(),
        .start_backward(),.we_to_dram(),.wdata_to_dram(),.transfer_done(),
        .filter_ids(),.filter_channel_ids(),.ifmap_ids(),.ifmap_channel_ids(),
        .psum_ids(),.psum_channel_ids());

    // GLB backdoor
    task wglb(input int t,a, input [15:0] v);
        int s; s=a>>2;
        case(t) 0:case(a&3) 0:DUT.GLB.U1_IFMAP.U0_0.mem[s]=v;
        1:DUT.GLB.U1_IFMAP.U0_1.mem[s]=v;2:DUT.GLB.U1_IFMAP.U1_0.mem[s]=v;
        3:DUT.GLB.U1_IFMAP.U1_1.mem[s]=v; endcase
        1:case(a&3) 0:DUT.GLB.U2_FILTER.U0_0.mem[s]=v;
        1:DUT.GLB.U2_FILTER.U0_1.mem[s]=v;2:DUT.GLB.U2_FILTER.U1_0.mem[s]=v;
        3:DUT.GLB.U2_FILTER.U1_1.mem[s]=v; endcase
        2:case(a&3) 0:DUT.GLB.U3_BIAS.U0_0.mem[s]=v;
        1:DUT.GLB.U3_BIAS.U0_1.mem[s]=v;2:DUT.GLB.U3_BIAS.U1_0.mem[s]=v;
        3:DUT.GLB.U3_BIAS.U1_1.mem[s]=v; endcase
        endcase
    endtask

    integer i;
    initial begin
        $display("=== v6: Parameter verification ===");
        reset_n=0; repeat(20) @(posedge core_clk); reset_n=1; repeat(10) @(posedge core_clk);

        // Load GLB
        for(i=0;i<64;i=i+1) wglb(0,i,(i+1)*256);
        wglb(1,0,16'h0100); wglb(1,1,0); wglb(1,2,0);
        wglb(1,3,0); wglb(1,4,16'h0200); wglb(1,5,0);
        wglb(1,6,0); wglb(1,7,0); wglb(1,8,16'h0100);
        wglb(2,0,0);

        // Load scan chain
        cfg_scan_chain("H:/moateff_trace/debug_campaign/tiny_config_lf.txt");
        repeat(20) @(posedge core_clk);

        // Dump ALL params at every level
        $display("\n=== Parameter values at each hierarchy level ===");
        $display("SCAN_CHAIN: e=%0d p=%0d q=%0d r=%0d t=%0d",
            DUT.SCAN_CHAIN.e, DUT.SCAN_CHAIN.p, DUT.SCAN_CHAIN.q,
            DUT.SCAN_CHAIN.r, DUT.SCAN_CHAIN.t);
        $display("SCHEDULER:  e=%0d p=%0d q=%0d r=%0d t=%0d",
            DUT.SCHEDULER.e, DUT.SCHEDULER.p, DUT.SCHEDULER.q,
            DUT.SCHEDULER.r, DUT.SCHEDULER.t);
        $display("Expected:    e=6 p=1 q=1 r=1 t=1");

        // Now force at ALL levels
        force DUT.SCAN_CHAIN.e = 8'd6;
        force DUT.SCAN_CHAIN.p = 5'd1;
        force DUT.SCAN_CHAIN.q = 3'd1;
        force DUT.SCAN_CHAIN.r = 2'd1;
        force DUT.SCAN_CHAIN.t = 3'd1;
        force DUT.SCHEDULER.e = 8'd6;
        force DUT.SCHEDULER.p = 5'd1;
        force DUT.SCHEDULER.q = 3'd1;
        force DUT.SCHEDULER.r = 2'd1;
        force DUT.SCHEDULER.t = 3'd1;
        @(posedge core_clk);

        $display("\n=== After force ===");
        $display("SCAN_CHAIN: e=%0d p=%0d q=%0d r=%0d t=%0d",
            DUT.SCAN_CHAIN.e, DUT.SCAN_CHAIN.p, DUT.SCAN_CHAIN.q,
            DUT.SCAN_CHAIN.r, DUT.SCAN_CHAIN.t);
        $display("SCHEDULER:  e=%0d p=%0d q=%0d r=%0d t=%0d",
            DUT.SCHEDULER.e, DUT.SCHEDULER.p, DUT.SCHEDULER.q,
            DUT.SCHEDULER.r, DUT.SCHEDULER.t);

        // Start test
        start=1; @(posedge core_clk); start=0;
        @(posedge core_clk);
        shared_pkg::start_pass=1; @(posedge core_clk); shared_pkg::start_pass=0;

        // Monitor until done or timeout
        for(i=0;i<300;i=i+1) begin
            @(posedge core_clk);
            if(i==0||i==1||i==5||i==10||i%50==0||DUT.SCHEDULER.done) begin
                $display("[C%0d T=%0t] SchSt=%0d PcSt=%0d | Ifmap d=%b we=%b gf=%b re=%b a=%0d t=(%0d,%0d) | Fil d=%b we=%b t=(%0d,%0d) | Is d=%b Os d=%b",
                    i, $time, DUT.SCHEDULER.state_crnt,
                    DUT.PROCESSING.nocs_top_inst.pass_controller_inst.state_crnt,
                    DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ifmap_noc_inst.done,
                    DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ifmap_noc_inst.we_to_gin_fifo,
                    DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ifmap_noc_inst.gin_fifo_full,
                    DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ifmap_noc_inst.re_from_glb,
                    DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ifmap_noc_inst.addr,
                    DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ifmap_noc_inst.row_tag,
                    DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ifmap_noc_inst.col_tag,
                    DUT.PROCESSING.nocs_top_inst.noc_controller_inst.filter_noc_inst.done,
                    DUT.PROCESSING.nocs_top_inst.noc_controller_inst.filter_noc_inst.we_to_gin_fifo,
                    DUT.PROCESSING.nocs_top_inst.noc_controller_inst.filter_noc_inst.row_tag,
                    DUT.PROCESSING.nocs_top_inst.noc_controller_inst.filter_noc_inst.col_tag,
                    DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ipsum_noc_inst.done,
                    DUT.PROCESSING.nocs_top_inst.noc_controller_inst.opsum_noc_inst.done);
            end
            if(DUT.SCHEDULER.done) begin
                $display("\n*** DONE! ***");
                i=9999;
            end
        end
        $display("\n=== v6 complete ===");
        $stop;
    end
endmodule
