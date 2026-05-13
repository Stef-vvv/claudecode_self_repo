module fifo_if_mem #(parameter FIFO_WIDTH = 64, DEPTH = 16, FIFO_ADDR_WIDTH = $clog2 (DEPTH))
(
    input wire 	wclk,
	input wire  reset,
	input wire 	Direct_Back_Path,
	input wire 	winc, 
	input wire  wfull, 
    input wire 	[FIFO_ADDR_WIDTH-1:0] waddr, 
	input wire  [FIFO_ADDR_WIDTH-1:0] raddr,
    input wire 	[FIFO_WIDTH-1:0] wdata,
    output wire [FIFO_WIDTH-1:0] rdata
);

    reg [FIFO_WIDTH-1:0] mem [DEPTH-1:0];
	reg w_en;
	
	always @(negedge wclk, posedge reset)
	begin
		if (reset)
			w_en <= 0;
		else
			w_en <= winc && !wfull;
	end
	
    always @(negedge wclk) begin
		if (!Direct_Back_Path)
		begin
			if (winc && (!wfull))
            mem[waddr] <= wdata;
		end
		else
		begin
			if (w_en)
            mem[waddr] <= wdata;
		end
    end
	
	assign rdata = mem[raddr]; 

endmodule
