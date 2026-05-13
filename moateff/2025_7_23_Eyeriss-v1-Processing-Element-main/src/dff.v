module flopr 
#(
    parameter DATA_WIDTH = 16
)(
    input                       clk, reset,
    input      [DATA_WIDTH-1:0] d, 
    output reg [DATA_WIDTH-1:0] q
);

    always @(negedge clk or posedge reset) begin
    if (reset) 
        q <= {DATA_WIDTH{1'b0}};
    else       
        q <= d;
    end

endmodule

