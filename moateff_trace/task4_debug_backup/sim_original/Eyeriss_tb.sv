`timescale 1ns / 1ps

import shared_pkg::*;
import test_pkg::*;

module eyeriss_tb;
    
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
    
        .H_WIDTH(H_WIDTH),
        .W_WIDTH(W_WIDTH),
        .R_WIDTH(R_WIDTH),
        .S_WIDTH(S_WIDTH),
        .E_WIDTH(E_WIDTH),
        .F_WIDTH(F_WIDTH),
        .C_WIDTH(C_WIDTH),
        .M_WIDTH(M_WIDTH),
        .N_WIDTH(N_WIDTH),
        .U_WIDTH(U_WIDTH),
        .m_WIDTH(m_WIDTH),
        .n_WIDTH(n_WIDTH),
        .e_WIDTH(e_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),
        .r_WIDTH(r_WIDTH),
        .t_WIDTH(t_WIDTH),
    
        .ROW_MAJOR(ROW_MAJOR),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
    
        .FIFO_WIDTH(FIFO_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
    
        .IFMAP_GLB_DEPTH(IFMAP_GLB_DEPTH),
        .FILTER_GLB_DEPTH(FILTER_GLB_DEPTH),
        .PSUM_GLB_DEPTH(PSUM_GLB_DEPTH),
        .BIAS_GLB_DEPTH(BIAS_GLB_DEPTH)
    ) DUT (
        .core_clk(core_clk),
        .link_clk(link_clk),
        .reset(reset),

        .scan_en(scan_en),
        .scan_in(scan_in),
        .scan_out(scan_out),

        .start(start),
        .busy(busy),
        .done(done),
        
        .start_pass(start_pass),
        .pass_done(pass_done),
        
        .ofmap_dump(ofmap_dump),
        .dump_done(dump_done),

        .words_num(words_num),
        .start_forward(start_forward),
        .transfer_type(transfer_type),
        .re_from_dram(re_from_dram),
        .rdata_from_dram(rdata_from_dram),
        .valid_from_dram(valid_from_dram),

        .start_backward(start_backward),
        .we_to_dram(we_to_dram),
        .wdata_to_dram(wdata_to_dram),
        .transfer_done(transfer_done),
        
        .filter_ids(filter_ids),
        .filter_channel_ids(filter_channel_ids),
        .ifmap_ids(ifmap_ids),
        .ifmap_channel_ids(ifmap_channel_ids),
        .psum_ids(psum_ids),
        .psum_channel_ids(psum_channel_ids)
    );
    
    initial begin
        fork
            forever begin
                #(CORE_CLK_PERIOD / 2.0) core_clk = ~core_clk;
            end

            forever begin
                #(LINK_CLK_PERIOD / 2.0) link_clk = ~link_clk;
            end
        join_none
    end
        
    initial begin
        run_test();
        $stop;
    end
        
endmodule

