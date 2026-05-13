`timescale 1ns/1ns

module testbench();

    parameter DATA_WIDTH = 16;
    parameter SIZE_IFMAP = 12;
    parameter SIZE_FILTER_SRAM = 3;
    parameter PSUM_SIZE = 32;
    parameter BUFFER_SIZE = 32;
    parameter W_PARAM = 1;
    parameter R_PARAM = 1;
    parameter N = 3;
    parameter KB = 32;
    parameter NUM_OF_FILTERS = 3;
    parameter ADDR_WIDTH_FILTER = $clog2(SIZE_FILTER_SRAM);
    parameter ADDR_WIDTH_IFMAP = $clog2(SIZE_IFMAP);
    parameter SIZE_GLOBAL = (KB * 8192) / DATA_WIDTH;
    parameter ADDR_WIDTH_GLOBAL = $clog2(SIZE_GLOBAL);

    reg clk = 0, rst = 1, start = 0;
    reg [1:0] mode = 0;
    reg [ADDR_WIDTH_IFMAP-1:0] stride = 1;
    reg [ADDR_WIDTH_FILTER-1:0] filter_size = 3;
    reg [ADDR_WIDTH_GLOBAL-1:0] last_global_index = 45;

    wire finish;

    toplevel # (
        .DATA_WIDTH(DATA_WIDTH),
        .SIZE_IFMAP(SIZE_IFMAP),
        .SIZE_FILTER_SRAM(SIZE_FILTER_SRAM),
        .PSUM_SIZE(PSUM_SIZE),
        .BUFFER_SIZE(BUFFER_SIZE),
        .W_PARAM(W_PARAM),
        .R_PARAM(R_PARAM),
        .N(N),
        .KB(KB),
        .NUM_OF_FILTERS(NUM_OF_FILTERS)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .mode(mode),
        .stride(stride),
        .filter_size(filter_size),
        .last_global_index(last_global_index),
        .finish(finish)
    );

    always begin #10;clk=~clk; end

    initial begin

        #20
        start = 0;
        rst = 0;

        #20
        start = 1;

        #20
        start = 0;

        #6000
        $stop;

    end

endmodule