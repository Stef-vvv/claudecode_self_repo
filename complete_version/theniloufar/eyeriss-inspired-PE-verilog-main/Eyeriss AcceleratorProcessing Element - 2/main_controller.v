module main_controller
        # (parameter OP_WIDTH = 5)
        (input clk,
        input rst,
        input start,
        input stop_read,
        input data_ready,
        input write_carry,
        input inner_carry,
        input stride_carry,
        input change_mode,
        input func,
        input psum_write_co,
        input psum_input_buf_valid,
        input [1:0] mode,
        input [OP_WIDTH - 1:0] op_cnt,
        output reg psum_cnt_en,
        output reg start_pipe,
        output reg reset_cont,
        output reg reset_reg,
        output reg reset_filter,
        output reg reset_inner, 
        output reg reset_stride,
        output reg w_psum, 
        output reg w_buf, 
        output reg data_read,
        output reg filter_read,
        output reg psum_inp_buf_ren,
        output reg psum_spad_ren,
        output reg w_en, 
        output reg inner_en, 
        output reg reg_en,
        output reg stride_en, 
        output reg filter_num_en,
        output reg rst_cnt_write_psum, 
        output reg psum_write_buf_cnt_en,
        output reg psum_write_ld,
        output reg op_cnt_en,
        output reg ex_psum_en,
        output reg stall,
        output reg mux_sel, 
        output reg done
        );
    
    // states
    parameter [3:0] S0 = 0, S1 = 1, S2 = 2, S3 = 3, S4 = 4, S5 = 5, S6 = 6, S7 = 7,
    S8 = 8, S9 = 9, S10 = 10, S11 = 11, S12 = 12, S13 = 13, S14 = 14, S15 = 15;
    reg [3:0] ps, ns;
    wire done_state;

    // wire for determining when we're done
    assign done_state = (mode == 2'd0 && op_cnt >= 1) ? 1'b1 
                    : (mode == 2'd1 && op_cnt >= 1) ? 1'b1 
                    : (mode == 2'd2) ? 1'b1 : 1'b0;    
    
    // output of each state
    always @(ps) begin
        {reset_cont, reset_reg, reset_filter, start_pipe, filter_read, data_read, w_buf, psum_cnt_en, ex_psum_en, w_psum, w_en,
        reg_en, inner_en, stride_en, reset_stride, reset_inner, filter_num_en, stall, done, op_cnt_en, rst_cnt_write_psum, psum_write_ld,
        psum_inp_buf_ren, psum_spad_ren, psum_write_buf_cnt_en} = 25'b0;
        case(ps) 
            S0: ;
            S1:  begin {reset_filter, reset_cont} = 2'b11; end
            S2:  begin start_pipe = 1'b1; end
            S3:  begin reset_reg = 1'b1; end
            S4:  begin {data_read, filter_read} = 2'b11; end
            S5:;
            S6:  begin {reg_en, inner_en} = 2'b11; end
            S7:  begin stall = 1'b1; end
            // S8:  begin {reset_inner, w_buf} = 2'b11; end
            S8:  begin {reset_inner, w_psum, psum_cnt_en, ex_psum_en} = 4'b1111; end
            S9:  begin stride_en = 1'b1; end
            S10: begin {w_en, reset_stride, filter_num_en} = 3'b111; end
            // S11: begin {reset_cont, done} = 2'b11; end
            S11: begin 
                reset_cont = 1'b1;
                done = (mode == 2'd0 && op_cnt >= 1) ? 1'b1 
                    : (mode == 2'd1 && op_cnt >= 1) ? 1'b1 
                    : (mode == 2'd2) ? 1'b1 : 1'b0;
                op_cnt_en = 1'b1;
              end
            S12: begin mux_sel = (change_mode) ? func : mux_sel; rst_cnt_write_psum = (change_mode && func); end
            S13: begin psum_write_ld = 1'b1; end
            S14: begin {psum_inp_buf_ren, psum_spad_ren} = (psum_input_buf_valid) ? 2'b11 : 2'b00; end
            S15: begin {psum_write_buf_cnt_en, w_buf} = 2'b11; end
        endcase     
    end

    // state transition
    always @(ps, start, stop_read, data_ready, inner_carry, stride_carry, write_carry, change_mode,
    func, done_state, psum_write_co, psum_input_buf_valid) begin
        case(ps) 
            S0: begin ns = start ? S1 : S0; end
            S1: begin ns = start ? S1 : S12; end
            S2: ns = S3;
            S3: begin ns = write_carry ? S11 : stop_read ? S5 : S4; end
            S4: begin ns = (~data_ready && inner_carry) ? S7 : (data_ready && inner_carry) ? S8 : stop_read ? S5 : S6; end
            S5: begin ns = stop_read ? S5 : S4; end
            S6: ns = S4;
            S7: begin ns = ~data_ready ? S7 : S8; end
            S8: begin ns = ~stride_carry ? S9 : S10; end
            S9: ns = S3;
            S10: ns = S3;
            S11: begin ns = (done_state) ? S12 : S2; end
            S12: begin ns = (~change_mode) ? S12 : (change_mode && (~func)) ? S2 : S13; end 
            S13: begin ns = S14; end
            S14: begin ns = (~psum_input_buf_valid) ? S14 : S15; end
            S15: begin ns = (~psum_write_co) ? S14 : S12; end
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