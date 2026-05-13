module reset_sync 
(
	input wire  clk, reset,
	output wire sync_reset
);

	reg sync;
	
	always @(negedge clk, posedge reset)
	begin
		if (reset)
		begin
			sync <= 'b0;
		end
		
		else
		begin
			sync <= {sync,1'b1};
		end
	end
	
	assign sync_reset = !sync;
	
endmodule 