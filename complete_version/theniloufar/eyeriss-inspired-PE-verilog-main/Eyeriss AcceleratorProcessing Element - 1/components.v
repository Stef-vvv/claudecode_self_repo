module adder#(parameter N = 4) 
(input [N-1:0] a, b,
output [N-1:0] out, output co);
    assign {co, out} = a + b;
endmodule

// module to apply mutliplication
module multiplier #(parameter N = 4)
    (input [N-1:0] a, b,
    output [N-1:0] out);
    wire [(2*N)-1:0] res;
    assign res = a * b;
    
    // seperate the first N bits
    assign out = res[N-1:0];
endmodule

// register to be used
module register #(parameter N = 8) 
    (input clk,
    input rst,
    input en,
    input [N-1:0] din,
    output reg [N-1:0] dout);

    always @(posedge clk) begin
        if (rst)
            dout <= {N{1'b0}}; 
        else begin
            if (en)
                dout <= din; 
        end            
    end
endmodule