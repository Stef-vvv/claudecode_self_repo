module adder 
#(
    parameter DATA_WIDTH = 16
)(
    input  wire signed [DATA_WIDTH - 1:0] x,
    input  wire signed [DATA_WIDTH - 1:0] y,
    output wire signed [DATA_WIDTH - 1:0] sum
);

    assign sum = x + y;
    
endmodule