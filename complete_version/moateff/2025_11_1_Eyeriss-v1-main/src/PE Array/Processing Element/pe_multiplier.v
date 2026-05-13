module multiplier
#(
    parameter DATA_WIDTH = 16
)(
    input wire clk, reset, enable,
    input wire signed [DATA_WIDTH - 1:0] x,
    input wire signed [DATA_WIDTH - 1:0] y,
    
    output reg signed [2 * DATA_WIDTH - 1:0] product
);

    always @(negedge clk or posedge reset) begin
        if (reset) begin
            product <= {DATA_WIDTH{1'b0}};
        end else if (enable) begin
            product <= x * y;
        end else begin
            product <= {DATA_WIDTH{1'b0}};
        end
    end
        
endmodule
