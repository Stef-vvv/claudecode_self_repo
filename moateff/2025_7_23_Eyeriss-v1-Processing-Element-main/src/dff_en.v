module flopenr 
#(
    parameter DATA_WIDTH = 16
)(
    input                        clk, reset,
    input                        en,
    input      [DATA_WIDTH-1:0] d, 
    output reg [DATA_WIDTH-1:0] q
);

    always @(negedge clk or posedge reset) begin
    if (reset) 
        q <= {DATA_WIDTH{1'b0}};
    else if (en)    
        q <= d;
    end

endmodule

