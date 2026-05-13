module muxx #(parameter FIFO_WIDTH = 64)
(
	input wire select,
	input wire [FIFO_WIDTH-1:0] in1,in0,
	output wire [FIFO_WIDTH-1:0] out
);

	assign out = (select) ? in1 : in0;

endmodule
