module main_controller
        (input clk,
        input rst,
        input start,
        input stop_read,
        input data_ready,
        input write_carry,
        input inner_carry,
        input stride_carry,
        output reg start_pipe,
        output reg reset_cont,
        output reg reset_reg,
        output reg reset_filter,
        output reg reset_inner, 
        output reg reset_stride, 
        output reg w_buf, 
        output reg data_read,
        output reg filter_read,
        output reg w_en, 
        output reg inner_en, 
        output reg reg_en,
        output reg stride_en, 
        output reg filter_num_en, 
        output reg stall, 
        output reg done
        );
    
    // states
    parameter [3:0] S0 = 0, S1 = 1, S2 = 2, S3 = 3, S4 = 4, 
    S5 = 5, S6 = 6, S7 = 7, S8 = 8, S9 = 9, S10 = 10, S11 = 11;
    reg [3:0] ps, ns;    
    
    // output of each state
    always @(ps) begin
        {reset_cont, reset_reg, reset_filter, start_pipe, filter_read, data_read, w_buf, w_en,
        reg_en, inner_en, stride_en, reset_stride, reset_inner, filter_num_en, stall, done} = 16'b0;
        case(ps) 
            S0: ;
            S1:  begin {reset_filter, reset_cont} = 2'b11; end
            S2:  begin start_pipe = 1'b1; end
            S3:  begin reset_reg = 1'b1; end
            S4:  begin {data_read, filter_read} = 2'b11; end
            S5:;
            S6:  begin {reg_en, inner_en} = 2'b11; end
            S7:  begin stall = 1'b1; end
            S8:  begin {reset_inner, w_buf} = 2'b11; end
            S9:  begin stride_en = 1'b1; end
            S10: begin {w_en, reset_stride, filter_num_en} = 3'b111; end
            S11: begin {reset_cont, done} = 2'b11; end
        endcase     
    end

    // state transition
    always @(ps, start, stop_read, data_ready, inner_carry, stride_carry, write_carry) begin
        case(ps) 
            S0: begin ns = start ? S1 : S0; end
            S1: begin ns = start ? S1 : S2; end
            S2: ns = S3;
            S3: begin ns = write_carry ? S11 : stop_read ? S5 : S4; end
            S4: begin ns = (~data_ready && inner_carry) ? S7 : (data_ready && inner_carry) ? S8 : stop_read ? S5 : S6; end
            S5: begin ns = stop_read ? S5 : S4; end
            S6: ns = S4;
            S7: begin ns = ~data_ready ? S7 : S8; end
            S8: begin ns = ~stride_carry ? S9 : S10; end
            S9: ns = S3;
            S10: ns = S3;
            S11: ns = S2;
            default: ns = S0;
        endcase
    end 

    always @(posedge clk) begin
        if(rst)
            ps <= S0;
        else
            ps <= ns;
    end

endmodule