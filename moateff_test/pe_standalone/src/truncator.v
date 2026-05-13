module truncator
#(
    parameter DATA_WIDTH = 16,
    parameter SEL_WIDTH  = $clog2(DATA_WIDTH)
)(
    input  wire [(2 * DATA_WIDTH) - 1:0] in,
    input  wire [SEL_WIDTH:0]            sel,
    
    output reg  [DATA_WIDTH-1:0]         out
);    
    
    integer i;
    always @(in or sel) begin
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin
            out[i] = in[sel + i];
        end
    end
    
endmodule
