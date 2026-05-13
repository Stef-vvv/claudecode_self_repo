module fifo_wr_ctrl #(
    parameter R_DATA_WIDTH = 8,
    parameter W_DATA_WIDTH = 16, 
    parameter MEM_WIDTH    = 16,
    parameter LIMIT        = 0,
    parameter FIFO_DEPTH   = 64,    
    parameter ADDR_WIDTH   = 4
)(
    input wire                    clk,
    input wire                    reset,
    input wire                    wr_request,
    input wire [ADDR_WIDTH:LIMIT] rd_ptr,
	
    output reg [ADDR_WIDTH:0] wr_ptr,
    output wire               wr_en,
    output wire               full_flag
);

    assign full_flag = (rd_ptr[ADDR_WIDTH - 1 : LIMIT] == wr_ptr[ADDR_WIDTH - 1 : LIMIT]) &&
                       (rd_ptr[ADDR_WIDTH] != wr_ptr[ADDR_WIDTH]);
                       
	assign wr_en = wr_request  & (~full_flag);

    wire wr_ptr_inc;
    assign wr_ptr_inc = wr_en;

    generate
        if (W_DATA_WIDTH == MEM_WIDTH) begin
            always @(negedge clk or posedge reset) begin
                if (reset) begin
                    wr_ptr <= 0;
                end else if (wr_ptr_inc) begin
                    wr_ptr <= wr_ptr + 1; 
                end
            end
        end else  begin
             always @(negedge clk or posedge reset) begin
                if (reset) begin
                    wr_ptr <= 0;
                end else if (wr_ptr_inc) begin
                    wr_ptr <= wr_ptr + (W_DATA_WIDTH / MEM_WIDTH); 
                end
             end
        end
    endgenerate
    
endmodule