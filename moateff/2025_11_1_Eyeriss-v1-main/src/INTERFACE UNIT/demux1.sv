module demuxx #(parameter FIFO_WIDTH = 64) 
(
    input wire [FIFO_WIDTH-1:0] in,      
    input wire select,      
    output wire [FIFO_WIDTH-1:0] out0,       
    output wire [FIFO_WIDTH-1:0] out1        
);

    assign out0 = (~select) ? in : 'b0;
    assign out1 = (select) ? in : 'b0;

endmodule
