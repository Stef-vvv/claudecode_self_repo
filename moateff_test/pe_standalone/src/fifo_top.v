module fifo_top #(
	parameter R_DATA_WIDTH  = 64,
    parameter W_DATA_WIDTH  = 16, 
    parameter FIFO_DEPTH    = 256,
    parameter ALMOST_THRESH = 2
)(
	input wire                     clk,
	input wire                     reset,
	input wire                     write_request,
	input wire                     read_request,
	input wire  [W_DATA_WIDTH-1:0] wr_data,

	output wire [R_DATA_WIDTH-1:0] rd_data,
	output wire                    full_flag,
	output wire                    empty_flag,
    
    output wire                    almost_full_flag,
    output wire                    almost_empty_flag
);
    
    localparam ADDR_WIDTH = $clog2(FIFO_DEPTH);
    localparam MEM_WIDTH = (R_DATA_WIDTH > W_DATA_WIDTH) ? W_DATA_WIDTH : R_DATA_WIDTH;
    localparam LIMIT = (R_DATA_WIDTH == W_DATA_WIDTH) ? 0 :((R_DATA_WIDTH > W_DATA_WIDTH) ? $clog2(R_DATA_WIDTH/W_DATA_WIDTH) : $clog2(W_DATA_WIDTH/R_DATA_WIDTH));
    
    wire [ADDR_WIDTH - 1:0] wr_addr, rd_addr;
    wire [ADDR_WIDTH:0] wr_ptr, rd_ptr;
    wire wr_en, rd_en;
    
    assign wr_addr = wr_ptr [ADDR_WIDTH - 1:0];
    assign rd_addr = rd_ptr [ADDR_WIDTH - 1:0];
    
    localparam INC_STEP = (W_DATA_WIDTH == R_DATA_WIDTH) ? 1 :((W_DATA_WIDTH > R_DATA_WIDTH) ? W_DATA_WIDTH/R_DATA_WIDTH : 1);
    localparam DEC_STEP = (R_DATA_WIDTH == W_DATA_WIDTH) ? 1 :((R_DATA_WIDTH > W_DATA_WIDTH) ? R_DATA_WIDTH/W_DATA_WIDTH : 1);
    
    wire [ADDR_WIDTH:0] count;

    assign almost_empty_flag = (count <= ALMOST_THRESH);
    assign almost_full_flag  = (count >= FIFO_DEPTH - ALMOST_THRESH);
    
    fifo_up_down_counter #(
        .WIDTH(ADDR_WIDTH + 1),
        .INC_STEP(INC_STEP),
        .DEC_STEP(DEC_STEP)
    ) counter_inst (
        .clk(clk),
        .reset(reset),
        .inc(wr_en),
        .dec(read_request),
        .count(count)
    );
        
    fifo_rd_ctrl #(
        .R_DATA_WIDTH(R_DATA_WIDTH),
        .W_DATA_WIDTH(W_DATA_WIDTH),
        .MEM_WIDTH(MEM_WIDTH),
        .LIMIT(LIMIT),
        .FIFO_DEPTH(FIFO_DEPTH), 
        .ADDR_WIDTH(ADDR_WIDTH) 
    ) read_ctrl (
        .clk(clk),
        .reset(reset),
        
        .rd_request(read_request),
        .wr_ptr(wr_ptr[ADDR_WIDTH:LIMIT]),
        .rd_ptr(rd_ptr),
        .rd_en(rd_en),
        .empty_flag(empty_flag)
    );

    fifo_wr_ctrl #(
        .R_DATA_WIDTH(R_DATA_WIDTH),
        .W_DATA_WIDTH(W_DATA_WIDTH),
        .MEM_WIDTH(MEM_WIDTH),
        .LIMIT(LIMIT), 
        .FIFO_DEPTH(FIFO_DEPTH),    
        .ADDR_WIDTH(ADDR_WIDTH) 
    ) write_ctrl (
        .clk(clk),
        .reset(reset),
        
        .wr_request(write_request),
        .rd_ptr(rd_ptr[ADDR_WIDTH:LIMIT]),
        .wr_ptr(wr_ptr),
        .wr_en(wr_en),
        .full_flag(full_flag)
    );

    fifo_mem #(
        .R_DATA_WIDTH(R_DATA_WIDTH),
        .W_DATA_WIDTH(W_DATA_WIDTH),        
        .MEM_WIDTH(MEM_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),    
        .ADDR_WIDTH(ADDR_WIDTH) 
    ) mem (
        .clk(clk), 
        .wr_en(wr_en),    
		.rd_en(rd_en),
        .wr_data(wr_data),       
        .wr_addr(wr_addr),    
        .rd_addr(rd_addr),
        .rd_data(rd_data)    
    );
    
endmodule