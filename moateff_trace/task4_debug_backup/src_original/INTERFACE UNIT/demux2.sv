module demuxxx #(parameter FIFO_WIDTH = 64) 
(
    input wire [FIFO_WIDTH-1:0] in,      
    input wire [1:0] select,      
    output wire [FIFO_WIDTH-1:0] out0,       
    output wire [FIFO_WIDTH-1:0] out1,
	output wire [FIFO_WIDTH-1:0] out2
);

    assign out0 = (select == 2'b00) ? in : 'b0;
    assign out1 = (select == 2'b10) ? in : 'b0;
	assign out2 = (select == 2'b01) ? in : 'b0;

endmodule
