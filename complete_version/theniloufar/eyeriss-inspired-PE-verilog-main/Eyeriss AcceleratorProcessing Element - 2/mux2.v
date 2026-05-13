module mux2 #(parameter N) (input [N-1:0] a, b, input src, output [N-1:0] out);
    assign out = (~src) ? a : b;
endmodule