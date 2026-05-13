module datapath
    #(parameter SIZE, 
    parameter DEPTH,
    parameter PAR_WRITE,
    parameter PAR_READ)
    (input clk, rst, write_en, cntW, cntR, input[(PAR_WRITE * SIZE)-1:0] din, output valid, ready, empty, full, output [(PAR_READ * SIZE)-1:0] dout);
    wire [3:0] write_ptr, read_ptr;
    wire [(PAR_READ * SIZE)-1:0] out_temp;

    // instances
    counter #(.DEPTH(DEPTH)) cnt1(clk, rst, cntW, PAR_WRITE, write_ptr);
    counter #(.DEPTH(DEPTH)) cnt2(clk, rst, cntR, PAR_READ, read_ptr);
    determiner d1(1'b0, PAR_WRITE, write_ptr, read_ptr, DEPTH, ready);
    determiner d2(1'b1, PAR_READ, write_ptr, read_ptr, DEPTH, valid);
    buffer #(.SIZE(SIZE), 
        .DEPTH(DEPTH), 
        .PAR_WRITE(PAR_WRITE), 
        .PAR_READ(PAR_READ))
        b(clk, rst, write_en, write_ptr, read_ptr, din, out_temp);

    // assigns
    assign full = ~ready;
    assign empty = ~valid;
    // assign dout = (valid) ? out_temp : {(PAR_READ * SIZE) * 1'bx}; 
    assign dout = out_temp; 
endmodule