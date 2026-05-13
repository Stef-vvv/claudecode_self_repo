module buffer_circ 
    #(parameter SIZE, 
    parameter DEPTH,
    parameter PAR_WRITE,
    parameter PAR_READ)
    (input clk, rst, wen, ren, input [(PAR_WRITE * SIZE)-1:0] din, output valid, ready, full, empty, output [(PAR_READ * SIZE)-1:0] dout);
    wire write_en, cntW, cntR;

    datapath #(
        .SIZE(SIZE), 
        .DEPTH(DEPTH), 
        .PAR_WRITE(PAR_WRITE), 
        .PAR_READ(PAR_READ))
        dp(clk, rst, write_en, cntW, cntR, din, valid, ready, empty, full, dout);
    controller cl(clk, rst, ren, valid, wen, ready, cntR, cntW, write_en);
endmodule

