`timescale 1ns/1ns

module testbench_third ();

    parameter DATA_WIDTH = 32, BUFFER_SIZE= 32, W_PARAM=1 , R_PARAM=1, SIZE_IFMAP= 12, SIZE_FILTER_SRAM = 10; 
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
        filter_size = 5;
        stride = 3;
        #20


        start = 1;
        #20
        start = 0;

        write_en_ifmap = 1;
        write_en_filter = 1;
        inp_buf_filter = 32'b00000000000000000000001001001110;
        inp_buf_ifmap =  34'b1000000000000000000000101101101110;
        #20

        write_en_ifmap = 1;
        write_en_filter = 1;
        inp_buf_filter = 32'b00000000000000000000101001101111;
        inp_buf_ifmap =  34'b0011111111111111111100011110101100;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  34'b0000000000000000000010111001111100;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  34'b0011111111111111111110000001010100;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  34'b0011111111111111111100001110110001;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  34'b0000000000000000000000011010011101;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  34'b0011111111111111111110010110001110;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  34'b0111111111111111111101010110111111;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  34'b1000000000000000000000001100101111;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  34'b0000000000000000000011001101111001;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  34'b0000000000000000000010111111001111;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  34'b0011111111111111111110001110110110;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  34'b0000000000000000000000000110110111;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  34'b0000000000000000000001101100010001;
        #20

        write_en_ifmap = 0;
        write_en_filter = 0;

        #1000

        write_en_ifmap = 1;
        write_en_filter = 1;
        inp_buf_filter = 32'b11111111111111111110111110001011;
        inp_buf_ifmap =  34'b0011111111111111111111101111101001;
        #20

        write_en_ifmap = 1;
        write_en_filter = 1;
        inp_buf_filter = 32'b11111111111111111111101100000101;
        inp_buf_ifmap =  34'b0100000000000000000011110010011101;
        #20

        write_en_ifmap = 1;
        write_en_filter = 1;
        inp_buf_filter = 32'b11111111111111111110010110101100;
        inp_buf_ifmap =  34'b1000000000000000000010110111111000;
        #20

        write_en_ifmap = 1;
        write_en_filter = 1;
        inp_buf_filter = 32'b11111111111111111111100110100100;
        inp_buf_ifmap =  34'b0000000000000000000001110100111100;
        #20

        write_en_ifmap = 1;
        write_en_filter = 1;
        inp_buf_filter = 32'b11111111111111111110111111110111;
        inp_buf_ifmap =  34'b0000000000000000000010111000001000;
        #20

        write_en_ifmap = 0;
        write_en_filter = 1;
        inp_buf_filter = 32'b11111111111111111110000101010101;
        #20

        write_en_ifmap = 0;
        write_en_filter = 0;

        #1000

        write_en_ifmap = 1;
        write_en_filter = 1;
        inp_buf_filter = 32'b11111111111111111101001000100001;
        inp_buf_ifmap =  34'b0000000000000000000001000001010010;
        #20

        write_en_ifmap = 1;
        write_en_filter = 1;
        inp_buf_filter = 32'b11111111111111111111011011000010;
        inp_buf_ifmap =  34'b0011111111111111111101111000001011;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  34'b0000000000000000000001100010010010;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  34'b0000000000000000000000001101001100;
        #20

        write_en_ifmap = 1;
        write_en_filter = 0;
        inp_buf_ifmap =  34'b0100000000000000000011001011001000;
        #20

        write_en_ifmap = 0;
        write_en_filter = 0;

        #5000
        $stop;
    end

endmodule 