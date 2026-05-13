module ifmap_glb 
#(	
	parameter FIFO_WIDTH = 64, 
	parameter DATA_WIDTH = 16, 
	parameter MEM_DEPTH = 16, 
	localparam ADDR_WIDTH = $clog2(MEM_DEPTH)
) (
    input wire clk,
	
	// port A                                        
	input wire we_a,                                      
	input wire re_a,                                      
	input wire [ADDR_WIDTH - 1:0] addr_a,       
	input wire [FIFO_WIDTH - 1:0] wdata_a,                  
	output reg [FIFO_WIDTH - 1:0] rdata_a,                  
	
	// port B                  
	input wire we_b,                                      
	input wire re_b,                                     
	input wire [ADDR_WIDTH - 1:0] addr_b, 
	input wire [DATA_WIDTH - 1:0] wdata_b,                        
	output reg [DATA_WIDTH - 1:0] rdata_b
); 


	wire [DATA_WIDTH - 1:0] rdata_a00, rdata_a01, rdata_a10, rdata_a11;

	always @(*) begin
        rdata_a = {rdata_a11, rdata_a10, rdata_a01, rdata_a00};
	end
	
	wire [ADDR_WIDTH - 1:0] addr_b_r;
	wire [DATA_WIDTH - 1:0] rdata_b00, rdata_b01, rdata_b10, rdata_b11;
	
	flop #(.DATA_WIDTH(ADDR_WIDTH)) dff (
        .clk(clk),
        .d(addr_b),
        .q(addr_b_r)
    );

	always @(*) begin
		case (addr_b_r[1:0])
			2'b00: rdata_b = rdata_b00;
			2'b01: rdata_b = rdata_b01;	
			2'b10: rdata_b = rdata_b10;
			2'b11: rdata_b = rdata_b11;
		endcase
	end

	dual_bram #(
		.DATA_WIDTH(DATA_WIDTH), 
		.MEM_DEPTH(MEM_DEPTH / 4)
	) U0_0 (
		.clk(clk),
			
		// port A
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[15:0]),
		.rdata_a(rdata_a00),
		
		// port B
		.we_b(we_b & (~addr_b[1]) & (~addr_b[0])), 
		.re_b(re_b & (~addr_b[1]) & (~addr_b[0])),	
		.addr_b(addr_b[ADDR_WIDTH - 1:2]),
		.wdata_b(wdata_b),
		.rdata_b(rdata_b00)
	); 
	
	dual_bram #(
		.DATA_WIDTH(DATA_WIDTH), 
		.MEM_DEPTH(MEM_DEPTH / 4)
	) U0_1 (
    .clk(clk),
		
		// port A
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[31:16]),
		.rdata_a(rdata_a01),
		
		// port B
		.we_b(we_b & (~addr_b[1]) & (addr_b[0])),
		.re_b(re_b & (~addr_b[1]) & (addr_b[0])),
		.addr_b(addr_b[ADDR_WIDTH - 1:2]),
		.wdata_b(wdata_b),
		.rdata_b(rdata_b01)
	); 
	
	dual_bram #(
		.DATA_WIDTH(DATA_WIDTH), 
		.MEM_DEPTH(MEM_DEPTH / 4)
	) U1_0 (
		.clk(clk),
			
		// port A
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[47:32]),
		.rdata_a(rdata_a10),
		
		// port B
		.we_b(we_b & (addr_b[1]) & (~addr_b[0])),
		.re_b(re_b & (addr_b[1]) & (~addr_b[0])),
		.addr_b(addr_b[ADDR_WIDTH - 1:2]),
		.wdata_b(wdata_b),
		.rdata_b(rdata_b10)
	); 
	
	dual_bram #(
		.DATA_WIDTH(DATA_WIDTH), 
		.MEM_DEPTH(MEM_DEPTH / 4)
	) U1_1 (
		.clk(clk),
			
		// port A
		.we_a(we_a),
		.re_a(re_a),
		.addr_a(addr_a[ADDR_WIDTH - 1:2]),
		.wdata_a(wdata_a[63:48]),
		.rdata_a(rdata_a11),

		// port B
		.we_b(we_b & (addr_b[1]) & (addr_b[0])),
		.re_b(re_b & (addr_b[1]) & (addr_b[0])),
		.addr_b(addr_b[ADDR_WIDTH - 1:2]),
		.wdata_b(wdata_b),
		.rdata_b(rdata_b11)
	);
	 
endmodule
