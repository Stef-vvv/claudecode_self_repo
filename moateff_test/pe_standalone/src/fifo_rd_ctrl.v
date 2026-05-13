module fifo_rd_ctrl #(
    parameter R_DATA_WIDTH = 16,
    parameter W_DATA_WIDTH = 16,
    parameter MEM_WIDTH    = 16,
    parameter LIMIT        = 0,
    parameter FIFO_DEPTH   = 256,    
    parameter ADDR_WIDTH   = 4
)(
    input wire                    clk,
    input wire                    reset,
    input wire                    rd_request,
    input wire [ADDR_WIDTH:LIMIT] wr_ptr,
	
    output reg [ADDR_WIDTH:0] rd_ptr,
    output wire                rd_en,
    output wire               empty_flag
);

    assign empty_flag = (wr_ptr[ADDR_WIDTH : LIMIT] == rd_ptr[ADDR_WIDTH : LIMIT]);
    
    assign rd_en = ~empty_flag;

    wire rd_ptr_inc;
    assign rd_ptr_inc = rd_request & (~empty_flag);
    
    generate
        if (R_DATA_WIDTH == MEM_WIDTH) begin
            always @(negedge clk or posedge reset) begin
                if (reset) begin
                    rd_ptr <= 0;
                end else if (rd_ptr_inc) begin
                    rd_ptr <= rd_ptr + 1; 
                end
            end
        end else begin
             always @(negedge clk or posedge reset) begin
                if (reset) begin
                    rd_ptr <= 0;
                end else if (rd_ptr_inc) begin
                    rd_ptr <= rd_ptr + (R_DATA_WIDTH / MEM_WIDTH);
                end
             end
        end
    endgenerate

endmodule