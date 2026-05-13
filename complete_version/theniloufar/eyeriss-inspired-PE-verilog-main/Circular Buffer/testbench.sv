`timescale 1ns/1ns

`define HALF_CLK 5
`define CLK (2 * `HALF_CLK)
module testbench();
    parameter BUFFER_WIDTH = 16;
    parameter BUFFER_DEPTH = 8;
    parameter PAR_WRITE = 4;
    parameter PAR_READ = 1;

    reg clk;
    reg rstn;
    reg wen, ren, buffer_ready, valid, full, empty;
    reg [PAR_WRITE * BUFFER_WIDTH - 1 : 0] din;
    wire [PAR_READ * BUFFER_WIDTH - 1 : 0] dout;

    buffer_circ #(
        .SIZE(BUFFER_WIDTH),
        .DEPTH(BUFFER_DEPTH + 1),
        .PAR_WRITE(PAR_WRITE),
        .PAR_READ(PAR_READ)
    ) dut (
        .clk(clk),
        .rst(rstn),
        .ren(ren),
        .wen(wen), //write enable
        .din(din), //input data
        .dout(dout), //data out
        .ready(buffer_ready),
        .valid(valid), //one data is read
        .full(full),
        .empty(empty)
    );

    always @(clk)begin
        # `HALF_CLK
        clk <= ~clk;
    end
    
    //for writing
    initial begin
        clk = 0;
        rstn = 0;
        wen = 0;

        // 1
        #`CLK;
        rstn = 1;

        // 2
        #`CLK;
        rstn = 0;

        // 3
        #`CLK;
        wen = 1;
        ren = 0;
        din = {16'd4, 16'd3, 16'd2, 16'd1};

        // 4
        #`CLK;
        wen = 1;
        ren = 1;
        din = {16'd5, 16'd6, 16'd7, 16'd8};

        // 5
        #`CLK;
        wen = 1;
        ren = 1;
        din = {16'd19, 16'd16, 16'd14, 16'd10};

        // 6
        #`CLK;
        wen = 1;
        ren = 1;
        din = {16'd19, 16'd16, 16'd14, 16'd10};

        // 7
        #`CLK;
        wen = 1;
        ren = 1;
        din = {16'd19, 16'd16, 16'd14, 16'd10};

        // 8
        #`CLK;
        wen = 1;
        ren = 1;
        din = {16'd19, 16'd16, 16'd14, 16'd10};

        // 9
        #`CLK;
        wen = 1;
        ren = 1;
        din = {-16'd4, -16'd3, -16'd2, -16'd1};

        // 10
        #`CLK;
        wen = 1;
        ren = 1;
        din = {-16'd4, -16'd3, -16'd2, -16'd1};

        // 11
        #`CLK;
        wen = 1;
        ren = 1;
        din = {-16'd4, -16'd3, -16'd2, -16'd1};

        // 12
        #`CLK;
        wen = 1;
        ren = 0;
        din = {-16'd4, -16'd3, -16'd2, -16'd1};

        // 13
        #`CLK;
        wen = 0;
        ren = 0;
        din = {-16'd4, -16'd3, -16'd2, -16'd1};

        // 14
        #`CLK;
        wen = 0;
        ren = 1;
        // din = 16'd5;

        // 15
        #`CLK;
        wen = 0;
        ren = 1;
        // din = 16'd5;

        // 16
        #`CLK;
        wen = 0;
        ren = 1;
        // din = 16'd5;

        //17 
        #`CLK;
        wen = 0;
        ren = 1;
        // din = 16'd5;

        #`CLK;

        $stop;
        
    end
    
    // //for reading
    // initial begin
    // ren = 0;
    // #`CLK;
    // #`CLK;
    // #`CLK;
    // #`CLK;
    
    // ren = 1;
    // #`CLK;
    // #`CLK;
    // ren = 0;
    // end

endmodule
