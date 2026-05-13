`timescale 1ns/1ns

module testbench_second();

    parameter DATA_WIDTH = 16, BUFFER_SIZE= 32, W_PARAM=1 , R_PARAM=1, SIZE_IFMAP= 12, SIZE_FILTER_SRAM = 12; 
    parameter ADDR_WIDTH_FILTER = $clog2(SIZE_FILTER_SRAM);
    parameter ADDR_WIDTH_IFMAP = $clog2(SIZE_IFMAP);


    reg clk=0,rst=1,start=0, write_en_ifmap=0, write_en_filter=0;


    wire read_en_ifmap, read_en_filter, valid_ifmap, valid_filter, write_en_out, ready, stall, done;

    wire [DATA_WIDTH-1:0] inp_ifmap, inp_filter, out_top;
    reg [DATA_WIDTH-1:0] inp_buf_filter;

    reg [DATA_WIDTH+1:0] inp_buf_ifmap;

    wire [DATA_WIDTH+1:0] inp_ifmap_temp;

    reg [ADDR_WIDTH_FILTER-1:0] filter_size;

    reg [ADDR_WIDTH_IFMAP-1:0] stride;

    reg [2*DATA_WIDTH-1:0] mult;
    reg [DATA_WIDTH-1:0] mult_lsb;


    circular_buffer #(.DATA_WIDTH(DATA_WIDTH + 2), .BUFFER_SIZE(BUFFER_SIZE), .W_PARAM(W_PARAM), .R_PARAM(R_PARAM)) cb_ifmap
                        (.clk(clk), .rst(rst), .write_en(write_en_ifmap), .read_en(read_en_ifmap), .inp(inp_buf_ifmap), 
                        .full(), .empty(), .ready(), .valid(valid_ifmap), .data_out(inp_ifmap_temp));

    circular_buffer #(.DATA_WIDTH(DATA_WIDTH), .BUFFER_SIZE(BUFFER_SIZE), .W_PARAM(W_PARAM), .R_PARAM(R_PARAM)) cb_filter
                        (.clk(clk), .rst(rst), .write_en(write_en_filter), .read_en(read_en_filter), .inp(inp_buf_filter), 
                        .full(), .empty(), .ready(), .valid(valid_filter), .data_out(inp_filter));

    circular_buffer #(.DATA_WIDTH(DATA_WIDTH), .BUFFER_SIZE(BUFFER_SIZE), .W_PARAM(W_PARAM), .R_PARAM(R_PARAM)) cb_out
                        (.clk(clk), .rst(rst), .write_en(write_en_out), .read_en(), .inp(out_top), 
                        .full(), .empty(), .ready(ready), .valid(), .data_out());

    wire end_signal, start_signal;

    assign {start_signal, end_signal, inp_ifmap} = inp_ifmap_temp;

    toplevel #(
        .width(DATA_WIDTH),
        .SIZE_IFMAP(SIZE_IFMAP),
        .SIZE_FILTER_SRAM(SIZE_FILTER_SRAM)
    ) cut (
        .clk(clk), .rst(rst), .start(start), .ready(ready), .valid_ifmap(valid_ifmap), .valid_filter(valid_filter), .end_signal(end_signal),
        .filter_size(filter_size),
        .inp_buf_ifmap(inp_ifmap),
        .inp_buf_filter(inp_filter),
        .stride(stride),
        .out_buf(out_top),
        .read_en_filter_buf(read_en_filter), .read_en_ifmap_buf(read_en_ifmap), .write_en_buf(write_en_out), .stall(stall), .done_out(done)
    );

    always begin #10;clk=~clk; end

    initial begin
        #20 start=0; rst=0; write_en_ifmap=0; write_en_filter=0;
        filter_size = 4;
        stride = 2;
        #20


        start = 1;
        #20
        start = 0;

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  18'b101111111111010111;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  18'b000000000000101001;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap = 18'b001111111111010011;
        #20

        write_en_ifmap = 0;
        write_en_filter = 0;


        #1000

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap = 18'b000000000000001001;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap = 18'b000000000000011100;
        #20

        write_en_ifmap = 0;
        write_en_filter = 0;

        #1000

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap = 18'b010000000000101110;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap = 18'b100000000000011101;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap = 18'b001111111111001000;
        #20

        write_en_ifmap = 0;
        write_en_filter = 0;

        #1000

        write_en_ifmap = 1;
        write_en_filter = 1;
        inp_buf_filter = 16'b1111111111010111;
        inp_buf_ifmap =  18'b001111111111110110;
        #20

        write_en_ifmap = 1;
        write_en_filter = 1;
        inp_buf_filter = 16'b1111111111001001;
        inp_buf_ifmap =  18'b000000000000101010;
        #20

        write_en_ifmap = 0;
        write_en_filter = 1;
        inp_buf_filter = 16'b0000000000011110;
        #20

        write_en_ifmap = 0;
        write_en_filter = 1;
        inp_buf_filter = 16'b0000000000110000;
        #20

        write_en_ifmap = 0;
        write_en_filter = 1;
        inp_buf_filter = 16'b1111111111011011;
        #20

        write_en_ifmap = 0;
        write_en_filter = 1;
        inp_buf_filter = 16'b0000000000110100;
        #20

        write_en_ifmap = 0;
        write_en_filter = 1;
        inp_buf_filter = 16'b0000000000001000;
        #20

        write_en_ifmap = 0;
        write_en_filter = 0;

        #2000

        write_en_ifmap = 1;
        write_en_filter = 1;
        inp_buf_filter = 16'b0000000000100000;
        inp_buf_ifmap =  18'b001111111111010000;
        #20

        write_en_ifmap = 1;
        write_en_filter = 1;
        inp_buf_filter = 16'b0000000000101100;
        inp_buf_ifmap =  18'b011111111111000010;
        #20

        write_en_ifmap = 0;
        write_en_filter = 1;
        inp_buf_filter = 16'b0000000000110001;
        #20

        write_en_ifmap = 0;
        write_en_filter = 1;
        inp_buf_filter = 16'b1111111111100100;
        #20

        write_en_ifmap = 0;
        write_en_filter = 1;
        inp_buf_filter = 16'b1111111111001100;
        #20

        write_en_ifmap = 0;
        write_en_filter = 0;

        #5000
        $stop;
    end

endmodule 