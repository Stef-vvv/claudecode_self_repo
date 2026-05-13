module zero_skipping
#(
    parameter MEM_DEPTH  = 12,
    parameter DATA_WIDTH = 16,      
    parameter ADDR_WIDTH = $clog2(MEM_DEPTH)
)(
    input  wire                    clk,     
    input  wire                    reset,    
            
    input  wire                    shift,      
    input  wire                    w_en,   
    input  wire [DATA_WIDTH - 1:0] din,        
    
    input  wire [ADDR_WIDTH - 1:0] r_addr,
    output wire                    zero_flag    
);

    // Shift register array
    reg [0:0] zero_buffer [0:MEM_DEPTH - 1];
        
    // Write address pointer
    reg [$clog2(MEM_DEPTH)-1:0] w_addr; 
        
    integer i;
    // Process for shifting or writing data
    always @(negedge clk) begin
        if (shift) begin
            for (i = 0; i < MEM_DEPTH - 1; i = i + 1) begin
                zero_buffer[i] <= zero_buffer[i + 1];
            end
        end else if (w_en) begin
            zero_buffer[w_addr] <= (din == {DATA_WIDTH{1'b0}});
        end 
    end
    
    assign zero_flag = zero_buffer[r_addr];
    
    // Write address management
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            w_addr <= 'b0; 
        end else if (shift) begin
            w_addr <= w_addr - 1;
        end else if (w_en) begin
            w_addr <= w_addr + 1;
        end
    end     
                       
endmodule
