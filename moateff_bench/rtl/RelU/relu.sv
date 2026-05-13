module relu 
#(
    parameter DATA_WIDTH = 16
)(
    input  [DATA_WIDTH - 1:0] in,
    output [DATA_WIDTH - 1:0] out
);
    assign out = (in[DATA_WIDTH - 1] == 1'b0) ? in : {DATA_WIDTH{1'b0}};
endmodule
