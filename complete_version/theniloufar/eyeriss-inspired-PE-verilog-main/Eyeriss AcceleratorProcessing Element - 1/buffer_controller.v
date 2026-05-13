// size is set to 17 which is one plus 16
// as we needed one more cell
module buffer_controller 
    #(parameter SIZE = 17)
    (input clk,
    input rst,
    input wen,
    input ren, 
    input start_read,
    input start_write,
    input [$clog2(SIZE)-1:0] write_ptr,
    input [$clog2(SIZE)-1:0] read_ptr, 
    output reg full, 
    output reg ready,
    output reg empty,
    output reg valid);


    reg [1:0] ps=2'b00;
    reg [1:0] ns;
    parameter [1:0] S0 = 2'b00, S1 = 2'b01;

    always @(ps, wen) 
    begin
        case(ps) 
            S0: ns = wen ? S1 : S0;
            S1: ns = wen ? S1 : S0;
            default: ns = S0;
        endcase
    end 

    // determine valid and empty signals
    always @(posedge clk) 
    begin
        valid <= start_read;
        empty <= ~start_read;
    end

    always @(ps, start_read, start_write, write_ptr, read_ptr) 
    begin
        {full, ready} = 3'b0;
        case(ps) 
            S0: begin
                ready = start_write;
                full = ~start_write;
            end
            S1: begin
                ready = start_write;
                full = ~start_write;
            end
        endcase     
    end

    always @(posedge clk) begin
        if(rst)
            ps <= S0;
        else
            ps <= ns;
    end

endmodule