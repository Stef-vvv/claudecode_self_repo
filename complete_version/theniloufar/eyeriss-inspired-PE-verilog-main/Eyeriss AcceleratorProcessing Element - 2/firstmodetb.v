`timescale 1ns/1ns

module firstmodetb();

    parameter DATA_WIDTH = 16, BUFFER_SIZE= 32, W_PARAM=1 , R_PARAM=1, SIZE_IFMAP = 12, SIZE_FILTER_SRAM = 3, PSUM_SIZE = 32; 
    parameter ADDR_WIDTH_FILTER = $clog2(SIZE_FILTER_SRAM);
    parameter ADDR_WIDTH_IFMAP = $clog2(SIZE_IFMAP);


    reg clk=0,rst=1,start=0, write_en_ifmap=0, write_en_filter=0, write_en_psum_buf = 0;
    reg func, change_mode;
    reg [1:0] mode;

    wire read_en_ifmap, read_en_filter, valid_ifmap, valid_filter, write_en_out, ready, stall, done, read_en_psum_buf, valid_psum_buf;

    wire [DATA_WIDTH-1:0] inp_ifmap, inp_filter, out_top, inp_psum;
    reg [DATA_WIDTH-1:0] inp_buf_filter;
    reg [DATA_WIDTH-1:0] inp_buf_psum;

    reg [DATA_WIDTH+1:0] inp_buf_ifmap;

    wire [DATA_WIDTH+1:0] inp_ifmap_temp;

    reg [ADDR_WIDTH_FILTER-1:0] filter_size;

    reg [ADDR_WIDTH_IFMAP-1:0] stride;

    circular_buffer #(.DATA_WIDTH(DATA_WIDTH + 2), .BUFFER_SIZE(BUFFER_SIZE), .W_PARAM(W_PARAM), .R_PARAM(R_PARAM)) cb_ifmap
                        (.clk(clk), .rst(rst), .write_en(write_en_ifmap), .read_en(read_en_ifmap), .inp(inp_buf_ifmap), 
                        .full(), .empty(), .ready(), .valid(valid_ifmap), .data_out(inp_ifmap_temp));

    circular_buffer #(.DATA_WIDTH(DATA_WIDTH), .BUFFER_SIZE(BUFFER_SIZE), .W_PARAM(W_PARAM), .R_PARAM(R_PARAM)) cb_filter
                        (.clk(clk), .rst(rst), .write_en(write_en_filter), .read_en(read_en_filter), .inp(inp_buf_filter), 
                        .full(), .empty(), .ready(), .valid(valid_filter), .data_out(inp_filter));

    circular_buffer #(.DATA_WIDTH(DATA_WIDTH), .BUFFER_SIZE(BUFFER_SIZE), .W_PARAM(W_PARAM), .R_PARAM(R_PARAM)) cb_psum
                        (.clk(clk), .rst(rst), .write_en(write_en_psum_buf), .read_en(read_en_psum_buf), .inp(inp_buf_psum), 
                        .full(), .empty(), .ready(), .valid(valid_psum_buf), .data_out(inp_psum));

    circular_buffer #(.DATA_WIDTH(DATA_WIDTH), .BUFFER_SIZE(BUFFER_SIZE), .W_PARAM(W_PARAM), .R_PARAM(R_PARAM)) cb_out
                        (.clk(clk), .rst(rst), .write_en(write_en_out), .read_en(), .inp(out_top), 
                        .full(), .empty(), .ready(ready), .valid(), .data_out());

    wire end_signal, start_signal;
    assign {start_signal, end_signal, inp_ifmap} = inp_ifmap_temp;

    toplevel #(
        .width(DATA_WIDTH),
        .SIZE_IFMAP(SIZE_IFMAP),
        .SIZE_FILTER_SRAM(SIZE_FILTER_SRAM),
        .PSUM_SIZE(PSUM_SIZE)
    ) cut (
        .clk(clk), .rst(rst), .start(start), .ready(ready), .valid_ifmap(valid_ifmap), .valid_filter(valid_filter), .end_signal(end_signal),
        .filter_size(filter_size),
        .inp_buf_ifmap(inp_ifmap),
        .inp_buf_filter(inp_filter),
        .change_mode(change_mode),
        .func(func),
        .stride(stride),
        .out_buf(out_top),
        .mode(mode),
        .inp_buf_psum(inp_psum),
        .valid_psum_buf(valid_psum_buf),
        .read_en_filter_buf(read_en_filter), .read_en_ifmap_buf(read_en_ifmap), .write_en_buf(write_en_out), .stall(stall), .done_out(done),
        .read_en_psum_buf(read_en_psum_buf));


    always begin #10;clk=~clk; end

    initial begin
        #20 start=0; rst=0; write_en_ifmap=0; write_en_filter=0;
        mode = 2'd0;
        filter_size = 3;
        stride = 1;
        #20


        start = 1;
        // set func for convolution 
        change_mode = 1;
        func = 0;
        #20
        start = 0;

        // filter values
        write_en_ifmap = 0;
        write_en_filter = 1;
        inp_buf_filter = -16'd129;
        #20

        write_en_ifmap = 0;
        write_en_filter = 1;
        inp_buf_filter = 16'd3;
        #20

        write_en_ifmap = 0;
        write_en_filter = 1;
        inp_buf_filter = 16'd41;
        #20

        // first ifmap line
        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap = {1'b1, 1'b0, 16'd14};
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap = {1'b0, 1'b0, 16'd39};
        #20

        // write_en_filter = 0;
        // #940

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap = {1'b0, 1'b0, 16'd164};
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap = {1'b0, 1'b0, 16'd171};
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap = {1'b0, 1'b0, -16'd6};
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap = {1'b0, 1'b1, -16'd80};
        #20

        // second ifmap line
        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap = {1'b1, 1'b0, 16'd122};
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  {1'b0, 1'b0, 16'd9};
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  {1'b0, 1'b0, 16'd155};
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  {1'b0, 1'b0, -16'd51};
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  {1'b0, 1'b0, -16'd26};
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  {1'b0, 1'b1, 16'd147};
        #20

        write_en_ifmap = 0;
        write_en_filter = 0;

        // set change mode to zero
        change_mode = 0;

        #960

        // write_en_ifmap = 0;
        // write_en_filter = 1;
        // inp_buf_filter = 16'b0000000000111111;
        // #20

        // write_en_ifmap = 0;
        // write_en_filter = 1;
        // inp_buf_filter = 16'b1111111111000100;
        // #20



        // write_en_ifmap = 1;
        // write_en_filter = 1;
        // inp_buf_filter = 16'b0000000000101110;
        // inp_buf_ifmap =  18'b001111111111101110;
        // #20





        // write_en_ifmap = 1;
        // write_en_filter = 1;
        // inp_buf_filter = 16'b0000000000011111;
        // inp_buf_ifmap =  18'b000000000000100000;
        // #20



        // write_en_ifmap = 1;
        // write_en_filter = 1;
        // inp_buf_filter = 16'b0000000000101111;
        // inp_buf_ifmap =  18'b001111111111010000;
        // #20

        // write_en_ifmap = 1;
        // write_en_filter = 1;
        // inp_buf_filter = 16'b0000000000100100;
        // inp_buf_ifmap =  18'b001111111111001100;
        // #20

        // write_en_ifmap = 1;
        // write_en_filter = 1;
        // inp_buf_filter = 16'b1111111111101101;
        // inp_buf_ifmap =  18'b001111111111001111;
        // #20

        // write_en_ifmap = 1;
        // write_en_filter = 1;
        // inp_buf_filter = 16'b1111111111001110;
        // inp_buf_ifmap =  18'b001111111111101111;
        // #20

        // write_en_ifmap = 1;
        // write_en_filter = 1;
        // inp_buf_filter = 16'b1111111111011011;
        // inp_buf_ifmap =  18'b011111111111001111;
        // #20

        // write_en_ifmap = 0;
        // write_en_filter = 0;
        // write_en_ifmap = 0;
        // write_en_filter = 1;
        // inp_buf_filter = 16'b1111111111001110;
        // #20

        // write_en_ifmap = 0;
        // write_en_filter = 1;
        // inp_buf_filter = 16'b1111111111011011;
        // #20


        // write_en_ifmap = 1;
        // write_en_filter = 1;
        // inp_buf_filter = 4'b1000;
        // inp_buf_ifmap = 6'b011000;
        // #20
        #5000
        $stop;
    end

endmodule 	