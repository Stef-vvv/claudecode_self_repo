module fifo_wrapper#(
	parameter R_DATA_WIDTH = 16,
    parameter W_DATA_WIDTH = 64, 
    parameter FIFO_DEPTH   = 256,
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
    
    localparam WRITE_LIMIT = $clog2(R_DATA_WIDTH/W_DATA_WIDTH);
    localparam READ_LIMIT = $clog2(W_DATA_WIDTH/R_DATA_WIDTH);
    
    wire write_enable, read_enable;
    
    fifo_top #(
        .R_DATA_WIDTH(R_DATA_WIDTH),
        .W_DATA_WIDTH(W_DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .ALMOST_THRESH(ALMOST_THRESH)
    ) fifo_inst (
        .clk(clk),
        .reset(reset),
        .write_request(write_enable),
        .read_request(read_enable),
        .wr_data(wr_data),
        .rd_data(rd_data),
        .full_flag(full_flag),
        .empty_flag(empty_flag),
        .almost_full_flag(almost_full_flag),
        .almost_empty_flag(almost_empty_flag)
    );
    
    generate
        if (WRITE_LIMIT > 0) begin 
            fifo_flag_generator #(.WIDTH(WRITE_LIMIT)) write_enable_logic (
                .clk(clk),
                .reset(reset),
                .enable(write_request),
                .flag(write_enable)
            );
        end else begin 
            assign write_enable = write_request;
        end
    endgenerate
    
    
    generate
        if (READ_LIMIT > 0) begin 
            fifo_flag_generator #(.WIDTH(READ_LIMIT)) read_enable_logic (
                .clk(clk),
                .reset(reset),
                .enable(read_request),
                .flag(read_enable)
            );
        end else begin 
            assign read_enable = read_request;
        end
    endgenerate

endmodule
