module wfull #(parameter DEPTH = 16 , FIFO_ADDR_WIDTH = $clog2 (DEPTH))
(
	input wire 	wclk,
	input wire 	reset,      
	input wire 	winc,            
	input wire 	[FIFO_ADDR_WIDTH:0] wq2_rptr,   
	output wire [FIFO_ADDR_WIDTH-1:0] waddr,
	output wire [FIFO_ADDR_WIDTH:0] wptr,
	output wire wfull
);

	reg [FIFO_ADDR_WIDTH:0] waddrr;
	
	always @(negedge wclk, posedge reset)
	begin
		if (reset)
			waddrr <= 'b0;
		else if (winc && (!wfull))
			waddrr <= waddrr + 1;	
	end
	
	//synchronization
	
	reg [FIFO_ADDR_WIDTH:0] sync0,sync1;
	wire [FIFO_ADDR_WIDTH:0] sync_wq2_rptr;
	
	always @(negedge wclk, posedge reset)
	begin
		if (reset)
		begin
			sync0 <= 0;
			sync1 <= 0;
		end
		
		else
		begin
			sync0 <= wq2_rptr;
			sync1 <= sync0;
		end
	end
	
	assign sync_wq2_rptr = sync1;
	
	//converting from bin to gray
	
	assign wptr = (waddrr >> 1) ^ waddrr;
	
	//assign full flag and waddr
	
	assign wfull = (wptr[FIFO_ADDR_WIDTH] != sync_wq2_rptr[FIFO_ADDR_WIDTH] && wptr[FIFO_ADDR_WIDTH-1] != sync_wq2_rptr[FIFO_ADDR_WIDTH-1] && wptr[FIFO_ADDR_WIDTH-2:0] == sync_wq2_rptr[FIFO_ADDR_WIDTH-2:0]); 
	assign waddr = waddrr;
	
endmodule

	
	