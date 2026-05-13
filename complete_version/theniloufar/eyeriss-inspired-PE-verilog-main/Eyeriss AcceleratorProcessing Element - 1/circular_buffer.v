module circular_buffer #(parameter DATA_WIDTH = 8, parameter BUFFER_SIZE = 16, parameter W_PARAM = 4, parameter R_PARAM = 4)
                        (input clk, rst, write_en, read_en, input [DATA_WIDTH*W_PARAM-1:0] inp, 
                        output full, empty, ready, valid, output [DATA_WIDTH*R_PARAM-1:0] data_out);

    wire [DATA_WIDTH-1:0] write_ptr, read_ptr;
    wire can_write, can_read;

    buffer_controller #(.SIZE(BUFFER_SIZE + 1)) c1(.clk(clk), .rst(rst), .ren(read_en), .wen(write_en), .write_ptr(write_ptr), .read_ptr(read_ptr), .start_read(can_read), .start_write(can_write), .ready(ready), .valid(valid), .full(full), .empty(empty));
    buffer_fifo #(.WIDTH_DATA(DATA_WIDTH), .SIZE(BUFFER_SIZE+1), .W_PARAM(W_PARAM), .R_PARAM(R_PARAM)) fifo (.clk(clk), .rst(rst), .write_en(write_en), .read_en(read_en), .inp(inp), .able_write_out(can_write), .able_read_out(can_read), .w_pointer_out(write_ptr), .r_pointer_out(read_ptr), .output_data(data_out));

endmodule