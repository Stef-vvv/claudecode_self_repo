module data_read_controller 
    (input clk,
    input rst,
    input start_read, 
    input data_read, 
    input valid,
    input done,
    output reg ren, 
    output reg wen, 
    output reg finish_read, 
    output reg read_buf);
    reg [2:0] ps, ns;
    parameter[2:0] S0 = 0, S1 = 1, S2 = 2, S3 = 3, S4 = 4, S5 = 5;

    always @(posedge clk) begin
        if(rst)
            ps <= S0;
        else
            ps <= ns;
    end

    always @(ps, start_read, data_read, valid, done) begin
        case(ps) 
            S0: ns = start_read ? S1 : S0;
            S1: ns = ~valid ? S1 : S2;
            S2: ns = S3;
            S3: ns = data_read ? S5 : S4;
            S4: ns = S1;
            S5: ns = done ? S0 : S5;
            default: ns = S0;
        endcase
    end     
    
    always @(ps) begin
        {ren, wen, finish_read, read_buf} = 4'b0;
        case(ps) 
            S0: ;
            S1: ;
            S2: read_buf = 1'b1;
            S3: wen = 1'b1;
            S4: ren = 1'b1;
            S5: finish_read = 1'b1;
        endcase     
    end

endmodule