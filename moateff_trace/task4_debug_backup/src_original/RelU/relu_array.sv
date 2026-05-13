module relu_array 
#(
    parameter DATA_WIDTH = 16,
    parameter NUM_INPUTS = 4
)(
    input  [NUM_INPUTS * DATA_WIDTH-1:0] in,
    output [NUM_INPUTS * DATA_WIDTH-1:0] out
);

genvar i;
generate
    for (i = 0; i < NUM_INPUTS; i = i + 1) begin : relu_gen
	relu #(.DATA_WIDTH(DATA_WIDTH)) relu_inst (
	    .in(in[(i+1) * DATA_WIDTH-1 : i * DATA_WIDTH]),
	    .out(out[(i+1) * DATA_WIDTH-1 : i * DATA_WIDTH])
	);
    end
endgenerate

endmodule
