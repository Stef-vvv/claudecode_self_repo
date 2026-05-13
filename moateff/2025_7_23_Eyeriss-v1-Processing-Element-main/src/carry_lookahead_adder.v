module cla #(
    parameter width = 6       // Total width of the number
)(
    input  wire [width - 1 : 0] x,
    input  wire [width - 1 : 0] y,
    output wire [width - 1 : 0] sum
//    output wire cout,                    // Carry-out for unsigned addition
//    output wire overflow                 // Overflow flag for signed numbers
);

    /*============== Carry generation ============== */
    wire [width - 1 : 0] g, p;
    assign g = x & y;           // Generate
    assign p = x ^ y;           // Propagate

    /*============== Intermediate carries ==============*/
    wire [width : 0] c;
    assign c[0] = 1'b0;

    genvar i;
    generate
        for (i = 0; i < width; i = i + 1) begin : CARRY_CHAIN
            assign c[i + 1] = g[i] | (p[i] & c[i]);
        end
    endgenerate

//    assign cout = c[width];
    assign sum  = p ^ c[width - 1 : 0];

    /*============== Overflow Detection ==============*/
//    assign overflow = (x[width-1] & y[width-1] & ~sum[width-1]) | 
//                      (~x[width-1] & ~y[width-1] & sum[width-1]);

endmodule