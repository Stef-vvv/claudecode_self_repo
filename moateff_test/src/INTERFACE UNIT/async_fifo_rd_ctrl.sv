module rempty #(parameter DEPTH = 16, FIFO_ADDR_WIDTH = $clog2(DEPTH))
(
	input wire 	rclk,reset,             // GLB clock
	input wire 	rinc,
	input wire 	[FIFO_ADDR_WIDTH:0] rq2_wptr,
	output wire [FIFO_ADDR_WIDTH-1:0] raddr,
	output wire [FIFO_ADDR_WIDTH:0] rptr,
	output wire rempty
);

	reg [FIFO_ADDR_WIDTH:0] raddrr;
	
	always @(negedge rclk, posedge reset)
	begin
		if (reset)
			raddrr <= 'b0;
		
		else if (rinc && !rempty)
			raddrr <= raddrr + 1;
	end
	
	//synchronization
	
	reg [FIFO_ADDR_WIDTH:0] sync0,sync1;
	wire [FIFO_ADDR_WIDTH:0] sync_rq2_wptr;
	
	always @(negedge rclk, posedge reset)
	begin
		if (reset)
		begin
			sync0 <= 0;
			sync1 <= 0;
		end
		
		else
		begin
			sync0 <= rq2_wptr;
			sync1 <= sync0;
		end
	end
	
	assign sync_rq2_wptr = sync1;
	
	//converting from bin to gray
	
	assign rptr = (raddrr >> 1) ^ raddrr;
	
	//assign empty flag and raddr
	
	assign rempty = (rptr == sync_rq2_wptr);
	assign raddr = raddrr;
	
endmodule

	
	