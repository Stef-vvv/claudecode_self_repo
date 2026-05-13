module mux2x1
#(
    parameter DATA_WIDTH = 16
)(
    input  [DATA_WIDTH-1:0] in0,   // Input 0
    input  [DATA_WIDTH-1:0] in1,   // Input 1
    input                    sel,   // Select line
    
    output [DATA_WIDTH-1:0] out    // Output
);
    assign out = sel ? in1 : in0; // If sel is 1, output in1; else, output in0
endmodule

