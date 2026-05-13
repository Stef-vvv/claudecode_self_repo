module async_fifo #(parameter FIFO_WIDTH = 64, GLB_WIDTH = 16, DEPTH = 16, FIFO_ADDR_WIDTH = $clog2 (DEPTH), ADDR_WIDTH = 20)
(
	input wire 		wclk,rclk,core_clk,
	input wire      reset,core_reset,                    								  	
	input wire 		Direct_Back_Path,                                              
	input wire 		rinc_to_GLB,                                                   	
	input wire 		[1:0] ifmap_filter,                                                  	
	input wire 		ifmap_bias,
	input wire 		rinc_to_DRAM,                                                  	
	input wire 		read_from_GLB,                                                 	
	input wire 		read_from_DRAM,                                                	
	input wire 		DRAM_w_en,
	input wire      transfer,
	input wire 		valid_from_DRAM,                                               	
	input wire 		[FIFO_WIDTH-1:0] wdata_from_DRAM,                    	        
	input wire 		[FIFO_WIDTH-1:0] wdata_from_GLB,
	input wire      [ADDR_WIDTH-1:0] base_address,  
	input wire      increment,                    
	output wire 	[FIFO_WIDTH-1:0] rdata_to_ifmap_GLB,
	output wire     [FIFO_WIDTH-1:0] rdata_to_filter_GLB,rdata_to_bias_GLB, 
	output wire 	[FIFO_WIDTH-1:0] rdata_to_DRAM,
	output reg 		w_en_ifmap_GLB,                                                   
	output reg 		w_en_filter_GLB,                                                  
	output reg 		w_en_bias_GLB,
	output reg 		w_en_DRAM,                                                        
	output reg 		r_en_DRAM,                                                      
    output reg 		r_en_GLB,                                              
	output reg 		wfull,
	output reg      [ADDR_WIDTH-1:0] raddr_from_GLB, 
	output reg      [ADDR_WIDTH-1:0] write_address_to_ifmap_GLB,write_address_to_filter_GLB,write_address_to_bias_GLB
);

	// wires and regs

	wire 	[FIFO_ADDR_WIDTH-1:0] raddrr,waddrr;
	wire 	[FIFO_ADDR_WIDTH:0] rptr,wptr;
	wire 	valid;                         
	wire 	r_inc;
	wire    wfulll,remptyy; 
	wire 	[FIFO_WIDTH-1:0] wdata;
	wire 	[FIFO_WIDTH-1:0] rdata;
	wire 	[FIFO_WIDTH-1:0] rdata_to_GLB;
	wire    w_en_DRAM_;
	wire    wreset;
	wire    rreset;
	
	reset_sync U_RST_wclk
	(
	.clk(wclk), 
	.reset(reset),
	.sync_reset(wreset)
	);
	
	reset_sync U_RST_rclk
	(
	.clk(rclk), 
	.reset(reset),
	.sync_reset(rreset)
	);
	
	// inistantiations
	
	muxxx U_MUXXX
	(
	.select1(Direct_Back_Path),
	.in11(r_en_GLB),
	.in00(valid_from_DRAM),
	.out1(valid)
	);
	
	
	wfull U_WFULL
	(
	.wclk(wclk),
	.reset(wreset),      
	.winc(valid),            
	.wq2_rptr(rptr),   
	.waddr(waddrr),
	.wptr(wptr),
	.wfull(wfulll)
	);
	
	
	muxxx U_MUXXX_2
	(
	.select1(Direct_Back_Path),
	.in11(rinc_to_DRAM & (!remptyy)),
	.in00(rinc_to_GLB & (!remptyy)),
	.out1(r_inc)
	);
	
	rempty U_REMPTY
	(
	.rclk(rclk),
	.reset(rreset),      
	.rinc(r_inc),   
	.rq2_wptr(wptr),   
	.raddr(raddrr),
	.rptr(rptr),
	.rempty(remptyy)
	);

	muxx U_MUX
	(
	.select(Direct_Back_Path),
	.in1(wdata_from_GLB),
	.in0(wdata_from_DRAM),
	.out(wdata)
	);
	
	
	fifo_if_mem U_FIFO_MEM
	(
	.wclk(wclk),
	.reset(wreset),
	.waddr(waddrr),
	.raddr(raddrr),
	.winc(valid), 
	.wfull(wfulll),
	.wdata(wdata),
	.rdata(rdata),
	.Direct_Back_Path(Direct_Back_Path)
	);
	
	wire address_generator_en = (~Direct_Back_Path) ? r_inc : read_from_GLB;
	wire [ADDR_WIDTH-1:0] gen_address;
	wire [ADDR_WIDTH-1:0] write_address_to_GLB;

	assign write_address_to_GLB = (~Direct_Back_Path) ? gen_address : 0;
	
	address_generator U_address_gen
	(
	.core_clk(core_clk),
	.reset(core_reset),
	.Direct_Back_Path(Direct_Back_Path),
	.enable(address_generator_en),
	.transfer(transfer),
	.base_address(base_address),               
	.increment(increment),                     
	.address(gen_address)                    
	);
	
	
	demuxx U_DEMUXX
	(
	.in(rdata),      
	.select(Direct_Back_Path),      
	.out0(rdata_to_GLB),       
	.out1(rdata_to_DRAM) 
	);
	
	
	demuxxx U_DEMUXXX
	(
	.in(rdata_to_GLB),      
	.select(ifmap_filter),      
	.out0(rdata_to_ifmap_GLB),       
	.out1(rdata_to_filter_GLB),
	.out2(rdata_to_bias_GLB)
	);
	
	
	always @(*)
	begin
		w_en_ifmap_GLB = (!remptyy & (ifmap_filter == 0) & ifmap_bias);             	
		w_en_filter_GLB = (!remptyy & (ifmap_filter == 2'b10));                               			    
		w_en_bias_GLB = (!remptyy & (ifmap_filter == 2'b01) & ~ifmap_bias);                                 
		r_en_DRAM = (~wfulll & read_from_DRAM);                               
		wfull = wfulll;
		raddr_from_GLB = (Direct_Back_Path) ? gen_address : 0;
		write_address_to_ifmap_GLB = (!ifmap_filter[1] && ifmap_bias) ? write_address_to_GLB : 0;
		write_address_to_filter_GLB = (ifmap_filter[1]) ? write_address_to_GLB : 0;
		write_address_to_bias_GLB = (!ifmap_filter[1] && !ifmap_bias) ? write_address_to_GLB : 0;
		r_en_GLB = (~wfulll & read_from_GLB);
	end
	
	assign w_en_DRAM_ = (~remptyy & DRAM_w_en);                                    
	
	always @(posedge rclk, posedge rreset)
	begin
		if (rreset)
			w_en_DRAM <= 0;
		else
			w_en_DRAM <= w_en_DRAM_;
	end
 	
	
endmodule
