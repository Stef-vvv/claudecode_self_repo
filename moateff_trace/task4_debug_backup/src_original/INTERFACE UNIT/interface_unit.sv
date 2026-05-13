module interface_unit #(
    parameter FIFO_WIDTH      = 64,
              GLB_WIDTH       = 16,
              DEPTH           = 16,
              FIFO_ADDR_WIDTH = $clog2(DEPTH),
			  ADDR_WIDTH      = 20
)(
    input  wire                  core_clk,
    input  wire                  link_clk,
    input  wire                  reset,

    // FIFO control
    input  wire [ADDR_WIDTH-1:0] words_num,

    // GLB
    // forward
    input  wire                  start_forward,
    input  wire [1:0]            ifmap_filter_bias_transfer,
    
    output wire                  w_en_ifmap_GLB,
    output wire [FIFO_WIDTH-1:0] rdata_to_ifmap_GLB,
	output wire [ADDR_WIDTH-1:0] write_address_to_ifmap_GLB,

    output wire                  w_en_filter_GLB,
    output wire [FIFO_WIDTH-1:0] rdata_to_filter_GLB,
    output wire [ADDR_WIDTH-1:0] write_address_to_filter_GLB,

    output wire                  w_en_bias_GLB,
    output wire [FIFO_WIDTH-1:0] rdata_to_bias_GLB,
    output wire [ADDR_WIDTH-1:0] write_address_to_bias_GLB,

    // backward
    input  wire                  start_backward,
    output wire                  r_en_GLB,
    input  wire [FIFO_WIDTH-1:0] wdata_from_GLB,
    output wire [ADDR_WIDTH-1:0] raddr_from_GLB,
    
    output wire                  transfer_done,

    // DRAM
    // forward
    output wire                  r_en_DRAM,
    input  wire                  valid_from_DRAM,
    output wire [FIFO_WIDTH-1:0] rdata_to_DRAM,

    // backward
    output wire                  w_en_DRAM,
    input  wire [FIFO_WIDTH-1:0] wdata_from_DRAM
);
    
    wire       ifmap_transfer_done;
    wire       filter_transfer_done;
    wire       bias_transfer_done;
    wire       for_transfer_done;
    wire       back_transfer_done;
    
    assign for_transfer_done = ifmap_transfer_done | filter_transfer_done | bias_transfer_done;
    assign transfer_done = for_transfer_done | back_transfer_done;
    
    wire       Direct_Back_Path;
    wire       [1:0] ifmap_filter;
    wire       ifmap_bias;
    wire       read_from_DRAM;
    wire       rinc_to_GLB;
    wire       read_from_GLB;
    wire       rinc_to_DRAM;
	wire       DRAM_w_en;
    wire       increment;
	wire 	   wclk,rclk;
	wire       core_reset,link_reset;
	wire       wfull;
    wire       transfer;
    
    wire [ADDR_WIDTH-1:0] base_address;
    
    assign base_address = 0;

	reset_sync U_RST_core
	(
	.clk(core_clk), 
	.reset(reset),
	.sync_reset(core_reset)
	);
	
	reset_sync U_RST_link
	(
	.clk(link_clk), 
	.reset(reset),
	.sync_reset(link_reset)
	);

	clk_mux U_CLK_MUX_1 
	(
	.link_clk(link_clk),      
    .core_clk(core_clk),  
    .enable(transfer),     
    .Direct_Back_Path(Direct_Back_Path),        
    .reset(reset),        
    .clk_out(wclk) 	
	);
	
	
	clk_mux U_CLK_MUX_2
	(
	.link_clk(link_clk),      
    .core_clk(core_clk),  
    .enable(transfer),     
    .Direct_Back_Path(~Direct_Back_Path),        
    .reset(reset),        
    .clk_out(rclk) 	
	);
	
    controller #(.ADDR_WIDTH(ADDR_WIDTH)) U0_CONTROLLER (
        .core_clk(core_clk),
        .link_clk(link_clk),
		.core_reset(core_reset),
		.link_reset(link_reset),
        .words_num(words_num),
        .ifmap_filter_bias_transfer(ifmap_filter_bias_transfer),
        .start_forward(start_forward),
        .valid_from_DRAM(valid_from_DRAM),
        .start_backward(start_backward),
		.wfull(wfull),
        .Direct_Back_Path(Direct_Back_Path),
        .ifmap_filter(ifmap_filter),
        .ifmap_bias(ifmap_bias),
        .read_from_DRAM(read_from_DRAM),
        .rinc_to_GLB(rinc_to_GLB),
        .read_from_GLB(read_from_GLB),
        .rinc_to_DRAM(rinc_to_DRAM),
		.DRAM_w_en(DRAM_w_en),
        .back_transfer_done(back_transfer_done),
        .ifmap_transfer_done(ifmap_transfer_done),
        .filter_transfer_done(filter_transfer_done),
        .bias_transfer_done(bias_transfer_done),
        .increment(increment),
        .transfer(transfer)
    );

    async_fifo #(.FIFO_WIDTH(FIFO_WIDTH), .GLB_WIDTH(GLB_WIDTH), .DEPTH(DEPTH), .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH), .ADDR_WIDTH(ADDR_WIDTH))U1_FIFO (
		.wclk(wclk),
		.rclk(rclk),
        .core_clk(core_clk),
        .reset(reset),
        .core_reset(core_reset),
        .Direct_Back_Path(Direct_Back_Path),
        .rinc_to_GLB(rinc_to_GLB),
        .ifmap_filter(ifmap_filter),
        .ifmap_bias(ifmap_bias),
        .rinc_to_DRAM(rinc_to_DRAM),
        .read_from_GLB(read_from_GLB),
        .read_from_DRAM(read_from_DRAM),
        .DRAM_w_en(DRAM_w_en),
        .valid_from_DRAM(valid_from_DRAM),
        .wdata_from_DRAM(wdata_from_DRAM),
        .wdata_from_GLB(wdata_from_GLB),
        .base_address(base_address),
        .increment(increment),
        .rdata_to_ifmap_GLB(rdata_to_ifmap_GLB),
        .rdata_to_filter_GLB(rdata_to_filter_GLB),
        .rdata_to_bias_GLB(rdata_to_bias_GLB),
        .rdata_to_DRAM(rdata_to_DRAM),
        .w_en_ifmap_GLB(w_en_ifmap_GLB),
        .w_en_filter_GLB(w_en_filter_GLB),
        .w_en_bias_GLB(w_en_bias_GLB),
        .w_en_DRAM(w_en_DRAM),
        .r_en_DRAM(r_en_DRAM),
        .r_en_GLB(r_en_GLB),
        .wfull(wfull),
        .raddr_from_GLB(raddr_from_GLB),
        .write_address_to_ifmap_GLB(write_address_to_ifmap_GLB),
        .write_address_to_filter_GLB(write_address_to_filter_GLB),
        .write_address_to_bias_GLB(write_address_to_bias_GLB),
		.transfer(transfer)
    );

endmodule
