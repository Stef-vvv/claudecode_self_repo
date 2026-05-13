module mux2x1
#(
    parameter DATA_WIDTH = 16
)(
    input  [DATA_WIDTH-1:0] in0,   
    input  [DATA_WIDTH-1:0] in1,   
    input                    sel,   
    
    output [DATA_WIDTH-1:0] out   
);
    assign out = sel ? in1 : in0; 
endmodule

