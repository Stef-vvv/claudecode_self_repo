module filter_spad
#(
    parameter MEM_DEPTH  = 224,     
    parameter DATA_WIDTH = 16,       
    parameter ADDR_WIDTH = $clog2(MEM_DEPTH)
)(
    input  wire                    clk,       
    input  wire                    reset,    
    
    input  wire [ADDR_WIDTH - 1:0] spad_depth, 
    
    input  wire                    w_en,    
    input  wire [DATA_WIDTH - 1:0] din,    
    
    input  wire                    r_en,   
    input  wire [ADDR_WIDTH - 1:0] r_addr,   
    output reg [DATA_WIDTH-1:0]    dout,    
    
    output wire                    full,     
    output wire                    empty    
);

    // Memory array using FPGA's internal BRAM
    reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];
    
    // Write address pointer
    reg [$clog2(MEM_DEPTH)-1:0] w_addr; 
    
    // Memory write and read logic
    always @(negedge clk) begin
        if (w_en) begin
            mem[w_addr] <= din; 
        end
        if (r_en) begin
            dout <= mem[r_addr]; 
        end
    end
    
    // Write address management
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            w_addr <= 'b0;
        end else if (w_en) begin
            w_addr <= w_addr + 1;
        end
    end
    
    // Full and empty flag assignments
    assign full  = (w_addr == spad_depth) ? 1'b1 : 1'b0; 
    assign empty = (w_addr == r_addr) ? 1'b1 : 1'b0;   
        
endmodule
