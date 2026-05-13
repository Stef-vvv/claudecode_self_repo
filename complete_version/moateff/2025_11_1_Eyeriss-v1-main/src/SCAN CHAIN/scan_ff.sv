module scan_ff (
    input  wire clk,      
    input  wire reset,    
    input  wire scan_en,       
    input  wire scan_in,
    // input  wire d,       
    output wire q,        
    output wire scan_out        
);

    reg q_internal;

    always @(negedge clk or posedge reset) begin
        if (reset)
            q_internal <= 1'b0;
        else if (scan_en)
            q_internal <= /*(~scan_en) ? d :*/scan_in;
    end

    assign q = (~scan_en) & q_internal;
    assign scan_out = q_internal;

endmodule
