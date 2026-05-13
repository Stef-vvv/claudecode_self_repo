module flop
#(
    parameter DATA_WIDTH = 16
)(
    input wire clk,
    input wire [DATA_WIDTH-1:0] d, 
    output reg [DATA_WIDTH-1:0] q
);

    always @(negedge clk) begin      
        q <= d;
    end

endmodule

