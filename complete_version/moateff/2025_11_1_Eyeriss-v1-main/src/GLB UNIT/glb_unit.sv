(* keep_hierarchy = "yes" *)
module glb_unit 
#(
    parameter FIFO_WIDTH = 64, 
    parameter DATA_WIDTH = 16,
	parameter IFMAP_GLB_DEPTH = 16,
	parameter FILTER_GLB_DEPTH = 16,
	parameter PSUM_GLB_DEPTH = 16,
	parameter BIAS_GLB_DEPTH = 16,
    localparam IFMAP_GLB_ADDR_WIDTH = $clog2(IFMAP_GLB_DEPTH),
    localparam FILTER_GLB_ADDR_WIDTH = $clog2(FILTER_GLB_DEPTH),
    localparam PSUM_GLB_ADDR_WIDTH = $clog2(PSUM_GLB_DEPTH),
    localparam BIAS_GLB_ADDR_WIDTH = $clog2(BIAS_GLB_DEPTH)
) (
	input wire clk,
	
	/******************************************IFMAP***********************************************/

	// port A                                         
	input  wire we_a_ifmap,                                     
	input  wire [IFMAP_GLB_ADDR_WIDTH - 1:0] addr_a_ifmap,
	input  wire [FIFO_WIDTH - 1:0] wdata_a_ifmap,                        
	
	// port B
	input  wire re_b_ifmap,                                      
	input  wire [IFMAP_GLB_ADDR_WIDTH - 1:0] addr_b_ifmap,                       
	output wire [DATA_WIDTH - 1:0] rdata_b_ifmap,                                          
	
	
	/******************************************FILTER***********************************************/
	
	// port A                                         
    input  wire we_a_filter,                                     
    input  wire [FILTER_GLB_ADDR_WIDTH - 1:0] addr_a_filter,
    input  wire [FIFO_WIDTH - 1:0]  wdata_a_filter,                        
    
    // port B
    input  wire re_b_filter,                                      
    input  wire [FILTER_GLB_ADDR_WIDTH - 1:0] addr_b_filter,                       
    output wire [DATA_WIDTH - 1:0]  rdata_b_filter, 
	
	
    /******************************************BIAS***********************************************/
    
    // port A                                         
    input  wire we_a_bias,                                     
    input  wire [BIAS_GLB_ADDR_WIDTH - 1:0] addr_a_bias,
    input  wire [FIFO_WIDTH - 1:0] wdata_a_bias,                        
    
    // port B
    input  wire re_b_bias,                                      
    input  wire [BIAS_GLB_ADDR_WIDTH - 1:0] addr_b_bias,                       
    output wire [DATA_WIDTH - 1:0] rdata_b_bias,
    
    
	/******************************************PSUM***********************************************/
	
	// port A 
	input  wire we_a_psum,                                   
	input  wire re_a_psum,                                   
	input  wire [PSUM_GLB_ADDR_WIDTH - 1:0] addr_a_psum,
    input  wire [DATA_WIDTH - 1:0] wdata_a_psum,                                       
    output wire [FIFO_WIDTH - 1:0] rdata_a_psum,                                       
	
	// port B
	input  wire re_b_psum,                                     
	input  wire [PSUM_GLB_ADDR_WIDTH - 1:0] addr_b_psum,            
	output wire [DATA_WIDTH - 1:0] rdata_b_psum
);

	/******************************************IFMAP***********************************************/
	ifmap_glb #(
        .FIFO_WIDTH(FIFO_WIDTH), 
        .DATA_WIDTH(DATA_WIDTH), 
        .MEM_DEPTH(IFMAP_GLB_DEPTH)
    ) U1_IFMAP (
        .clk(clk),
        
        // port A                                        
        .we_a(we_a_ifmap),                                      
        .re_a(1'b0),                                      
        .addr_a(addr_a_ifmap),
        .wdata_a(wdata_a_ifmap),                         
        .rdata_a(), 
        
        // port B                         
        .we_b(1'b0),                                      
        .re_b(re_b_ifmap),                                     
        .addr_b(addr_b_ifmap),
        .wdata_b(16'b0),
        .rdata_b(rdata_b_ifmap)
	); 

	/******************************************FILTER***********************************************/
	filter_glb #(
        .FIFO_WIDTH(FIFO_WIDTH), 
        .DATA_WIDTH(DATA_WIDTH), 
        .MEM_DEPTH(FILTER_GLB_DEPTH)
    ) U2_FILTER (
        .clk(clk),
        
        // port A                                        
        .we_a(we_a_filter),                                      
        .re_a(1'b0),                                      
        .addr_a(addr_a_filter),
        .wdata_a(wdata_a_filter),                         
        .rdata_a(), 
        
        // port B                         
        .we_b(1'b0),                                      
        .re_b(re_b_filter),                                     
        .addr_b(addr_b_filter),
        .wdata_b(16'b0),
        .rdata_b(rdata_b_filter)
	); 
    
    /******************************************BIAS***********************************************/
    bias_glb #(
        .FIFO_WIDTH(FIFO_WIDTH), 
        .DATA_WIDTH(DATA_WIDTH), 
        .MEM_DEPTH(BIAS_GLB_DEPTH)
    ) U3_BIAS (
        .clk(clk),
        
        // port A                                        
        .we_a(we_a_bias),                                      
        .re_a(1'b0),                                      
        .addr_a(addr_a_bias),
        .wdata_a(wdata_a_bias),                         
        .rdata_a(), 
        
        // port B                         
        .we_b(1'b0),                                      
        .re_b(re_b_bias),                                     
        .addr_b(addr_b_bias),
        .wdata_b(16'b0),
        .rdata_b(rdata_b_bias)
    ); 
    
    /******************************************PSUM***********************************************/
	psum_glb #(
        .FIFO_WIDTH(FIFO_WIDTH), 
        .DATA_WIDTH(DATA_WIDTH), 
        .MEM_DEPTH(PSUM_GLB_DEPTH)
    ) U4_PSUM (
        .clk(clk),
        
        // port A                                        
        .we_a(we_a_psum),                                      
        .re_a(re_a_psum),                                      
        .addr_a(addr_a_psum),
        .wdata_a(wdata_a_psum),                         
        .rdata_a(rdata_a_psum), 
        
        // port B                         
        .we_b(1'b0),                                      
        .re_b(re_b_psum),                                     
        .addr_b(addr_b_psum),
        .wdata_b(16'b0),
        .rdata_b(rdata_b_psum)
	); 
  
endmodule
