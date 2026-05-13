module ifmap_spad
#(
    parameter MEM_DEPTH  = 12,   
    parameter DATA_WIDTH = 16,   
    parameter ADDR_WIDTH = $clog2(MEM_DEPTH)
)(
    input  wire                    clk,     
    input  wire                    reset,    
    
    input  wire [ADDR_WIDTH - 1:0] spad_depth,  
        
    input  wire                    shift,      
    input  wire                    w_en,   
    input  wire [DATA_WIDTH - 1:0] din,        
    
    input  wire [ADDR_WIDTH - 1:0] r_addr,
    input  wire                    r_en,   
    output reg  [DATA_WIDTH - 1:0] dout,    
    
    output wire full,     
    output wire empty     
);

    reg [DATA_WIDTH-1:0] shift_reg [0:MEM_DEPTH-1];
        
    reg [$clog2(MEM_DEPTH)-1:0] w_addr; 
        
    integer i;
    always @(negedge clk) begin
        if (shift) begin
            for (i = 0; i < MEM_DEPTH - 1; i = i + 1) begin
                shift_reg[i] <= shift_reg[i + 1];
            end
        end else if (w_en) begin
            shift_reg[w_addr] <= din; 
        end 
        if (r_en) begin
            dout <= shift_reg[r_addr]; 
        end
    end
    
    
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            w_addr <= 'b0; 
        end else if (shift) begin
            w_addr <= w_addr - 1;
        end else if (w_en) begin
            w_addr <= w_addr + 1;
        end
    end
    
    assign full  = (w_addr == spad_depth) ? 1'b1 : 1'b0; 
    assign empty = (w_addr == r_addr) ? 1'b1 : 1'b0;     
                       
endmodule

     