// similar to data_read_controller
module filter_read_controller 
    (input clk,
    input rst,
    input start_read,
    input co, 
    input valid,
    input done,
    output reg ren, 
    output reg wen, 
    output reg finish_read, 
    output reg read_buf);
    
    // states
    parameter[2:0] S0 = 0, S1 = 1, S2 = 2, S3 = 3, S4 = 4, S5 = 5;
    reg [2:0] ps, ns;

    always @(posedge clk) begin
        if(rst)
            ps <= S0;
        else
            ps <= ns;
    end

    // state transition
    always @(ps) begin
        {finish_read, read_buf, ren, wen} = 4'b0;
        case(ps) 
            S0:;
            S1:;
            S2: read_buf = 1'b1;
            S3: wen = 1'b1;
            S4: ren = 1'b1;
            S5: finish_read = 1'b1;
        endcase     
    end

    always @(ps, rst, co, valid, done, start_read) begin
        case(ps) 
            S0: ns = start_read ? S1 : S0;
            S1: ns = ~valid ? S1 : S2;
            S2: ns = S3;
            S3: ns = co ? S5 : S4;
            S4: ns = S1;
            S5: ns = rst ? S0 : S5;
            default: ns = S0;
        endcase
    end     

endmodule
