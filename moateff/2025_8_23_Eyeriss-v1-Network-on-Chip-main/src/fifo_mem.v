module fifo_mem #(
    parameter R_DATA_WIDTH = 64,
    parameter W_DATA_WIDTH = 16,
    parameter MEM_WIDTH    = 16,
    parameter FIFO_DEPTH   = 256,    
    parameter ADDR_WIDTH   = 4
)(
    input  wire                      clk,
    input  wire                      wr_en,
	input  wire                      rd_en,	
    input  wire [ADDR_WIDTH - 1:0]   wr_addr,    
    input  wire [ADDR_WIDTH - 1:0]   rd_addr,
	
    input  wire [W_DATA_WIDTH - 1:0] wr_data,       
    output wire [R_DATA_WIDTH - 1:0] rd_data    
);
	
    reg [MEM_WIDTH - 1:0] mem [0:FIFO_DEPTH - 1];
	
    generate
        if (R_DATA_WIDTH > W_DATA_WIDTH) begin
			//integer j;
            /*=================================== Write operation ===================================*/
            always @(negedge clk) begin
                if (wr_en) begin
                    mem[wr_addr] <= wr_data;
                end
            end

            /*=============================== Read operation with FWFT ===============================*/
            genvar k;
				for (k = 0; k < R_DATA_WIDTH/MEM_WIDTH; k = k + 1) begin : read_mem
					assign rd_data[(k+1)*MEM_WIDTH-1 -: MEM_WIDTH] = (rd_en)? mem[rd_addr + k] : 'b0;
				end
        end else begin
            integer i;

            /*=================================== Write operation ===================================*/
            always @(negedge clk) begin
                if (wr_en) begin
                    for (i = 0; i < W_DATA_WIDTH/MEM_WIDTH; i = i + 1) begin
                    mem[wr_addr + i] <= wr_data[(i+1)*MEM_WIDTH-1 -: MEM_WIDTH];
                    end
                end
            end

            /*=============================== Read operation with FWFT ===============================*/
			assign rd_data = (rd_en)? mem[rd_addr] : 'b0;
        end
    endgenerate

endmodule