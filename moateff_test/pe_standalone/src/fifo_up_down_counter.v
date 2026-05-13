module fifo_up_down_counter #(
    parameter WIDTH    = 4,             
    parameter INC_STEP = 1,            
    parameter DEC_STEP = 1            
)(
    input  wire clk,                
    input  wire reset,
                   
    input  wire inc,               
    input  wire dec,                
    output reg  [WIDTH-1:0] count   
);

    always @(negedge clk or posedge reset) begin
        if (reset) begin
            count <= 0;
        end else begin
            case ({inc, dec})
                2'b00: count <= count;
                2'b10: count <= count + INC_STEP;   
                2'b01: count <= count - DEC_STEP; 
                2'b11: count <= count + INC_STEP - DEC_STEP;     
            endcase
        end
    end

endmodule
