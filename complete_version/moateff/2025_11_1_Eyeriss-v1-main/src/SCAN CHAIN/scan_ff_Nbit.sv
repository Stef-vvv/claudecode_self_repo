module scan_ff_Nbit #(parameter DATA_WIDTH = 4) (
    input  wire clk,             
    input  wire reset,             
    input  wire scan_en,               
    input  wire scan_in,                
    output wire [DATA_WIDTH - 1:0] q,       
    output wire scan_out                  
);
    
    wire [DATA_WIDTH:0] scan_w;

    assign scan_w[DATA_WIDTH] = scan_in;
    assign scan_out = scan_w[0];
        
    genvar i;
    generate
        for (i = DATA_WIDTH - 1; i >= 0; i = i - 1) begin : SCAN_FF
            scan_ff scan_ff_inst (
                .clk(clk),          
                .reset(reset),  
                .scan_en(scan_en),           
                .scan_in(scan_w[i+1]),   
                .q(q[i]),           
                .scan_out(scan_w[i])         
            );
        end
    endgenerate
    
endmodule
