module buffer_fifo  #(parameter WIDTH_DATA = 8, parameter SIZE = 17, parameter W_PARAM = 4, parameter R_PARAM = 4)
                ( input [WIDTH_DATA*W_PARAM-1:0] inp, input clk, rst, write_en, read_en,  output [$clog2(SIZE)-1:0] w_pointer_out, r_pointer_out, output reg [WIDTH_DATA*R_PARAM-1:0] output_data, output able_write_out, able_read_out);

    localparam ADDR_WIDTH = $clog2(SIZE);

    reg able_write, able_read;
    reg [ADDR_WIDTH-1:0] write_ptr = 0;            
    reg [WIDTH_DATA-1:0] buffer [0:SIZE-1]; 
    reg [ADDR_WIDTH-1:0] read_ptr_index = 0;   
    reg [ADDR_WIDTH-1:0] read_ptr = 0;

    integer i;

    always @(posedge clk) begin
        able_write = (write_ptr > read_ptr) ? (((SIZE - 1 - write_ptr) + read_ptr) >= W_PARAM) : (write_ptr < read_ptr) ? ((read_ptr - write_ptr - 1) >= W_PARAM) : (W_PARAM <= SIZE-1);
        if (rst) begin
            write_ptr <= 0;
        end 
        else if (write_en & able_write) begin
            for (i = W_PARAM; i > 0; i = i - 1) begin
                buffer[write_ptr] <= inp[((i*WIDTH_DATA)-1) -: WIDTH_DATA];
                write_ptr = ((write_ptr + 1) == SIZE) ? 0 : (write_ptr + 1);
            end
        end


        if (rst) begin
            read_ptr <= 0;
        end 
        else if (able_read & read_en) begin
            for (i = R_PARAM; i > 0; i = i - 1) begin                                                                                                           
                output_data[((i*WIDTH_DATA)-1) -: WIDTH_DATA] <= buffer[read_ptr];
                read_ptr = ((read_ptr + 1) == SIZE) ? 0 : (read_ptr + 1);
            end
        end

        able_read =  (write_ptr > read_ptr) ? ((write_ptr - read_ptr) >= R_PARAM) :
            (write_ptr < read_ptr) ? (((SIZE - read_ptr) + write_ptr) >= R_PARAM) : 0;
    end

    assign able_write_out = able_write;
    assign r_pointer_out = read_ptr;
    assign able_read_out = able_read;
    assign w_pointer_out = write_ptr; 
endmodule
