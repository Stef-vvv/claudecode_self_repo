module muxxx
(
	input wire select1,
	input wire in11,in00,
	output wire out1
);

	assign out1 = (select1) ? in11 : in00;

endmodule
