module controller_global
    #(parameter N = 5,
    parameter N_ADDR = $clog2(N))
    (input clk,
    input rst,
    input start,
    input last_PE,
    input last_filter,
    input done,
    input can_start,
    input end_read,
    input [N_ADDR-1:0] PE_index,
    input [0:N-1] sum_dones,
    input [0:N-1] ready_ifmap_bufs,
    input [0:N-1] ready_filter_bufs,
    input [0:N-1] valids,
    output reg ren_global,
    output reg wen_global,
    output reg write_addr_ld,
    output reg read_addr_en,
    output reg write_addr_en,
    output reg PE_number_en,
    output reg filter_number_en,
    output reg read_addr_clr,
    output reg PE_number_clr,
    output reg filter_number_clr,
    output reg func,
    output reg finish,
    output reg [0:N-1] rst_bufs,
    output reg [0:N-1] change_modes,
    output reg [0:N-1] write_en_ifmaps,
    output reg [0:N-1] write_en_filters,
    output reg [0:N-1] write_en_psum_bufs,
    output reg [0:N-1] read_en_bufs);

    integer i, j, k;

    // states
    parameter [3:0] s0 = 0, s1 = 1, s2 = 2, s3 = 3, s4 = 4, s5 = 5, s6 = 6, s7 = 7, s8 = 8, s9 = 9, s10 = 10, s11 = 11, s12 = 12, s13 = 13;
    reg [3:0] ps, ns;

    // update state
    always @(posedge clk) begin
        if (rst)
            ps <= s0;
        else
            ps <= ns;
    end

    // state transition
    always @(ps, start, last_filter, last_PE, end_read, can_start, done, sum_dones[PE_index], valids[PE_index]) begin
        case (ps) 
            s0: ns = start ? s1 : s0;
            s1: ns = start ? s1 : s2;
            s2: ns = s3;
            s3: ns = last_filter ? s4 : s3;
            s4: ns = last_PE ? s5 : s3;
            s5: ns = end_read ? s6 : s5;
            s6: ns = done ? s7 : s6;
            s7: ns = s8;
            s8: begin ns = ~sum_dones[PE_index] ? s8 : last_PE ? s11 : s9; end
            s9: ns = s10;
            s10: ns = valids[PE_index] ? s10 : s7;
            s11: ns = s12;
            s12: ns = valids[PE_index] ? s12 : s13;
            s13: ns = s13;
            default: ns = s0;
        endcase
    end 

    // output of each state
    always @(ps, can_start, PE_index, valids, valids[PE_index]) begin
        {read_addr_clr, PE_number_clr, filter_number_clr, wen_global, write_addr_en, write_addr_ld,
         ren_global, filter_number_en, read_addr_en, PE_number_en, func, finish} = 12'b0;
        for (k = 0; k < N; k = k + 1) begin
            rst_bufs[k] = 1'b0;
            write_en_filters[k] = 1'b0;
            write_en_ifmaps[k] = 1'b0;
            change_modes[k] = 1'b0;
            read_en_bufs[k] = 1'b0;
            write_en_psum_bufs[k] = 1'b0;
        end
        case (ps) 
            s0: ;
            s1: {read_addr_clr, write_addr_ld, PE_number_clr, filter_number_clr, rst_bufs[0]} = 5'b11111;
            s2: {ren_global, read_addr_en} = 2'b11;
            s3: begin
                    {write_en_filters[PE_index], ren_global} = 2'b11;
                    filter_number_en = ready_filter_bufs[PE_index] ? 1'b1 : 1'b0;
                    read_addr_en = ready_filter_bufs[PE_index] ? 1'b1 : 1'b0;
            end
            s4: begin 
                    {PE_number_en, filter_number_clr} = 2'b11;
                    PE_number_clr = last_PE ? 1'b1 : 1'b0;
            end
            s5: begin
                    {write_en_ifmaps[PE_index], ren_global} = 2'b11;
                    read_addr_en = ready_ifmap_bufs[PE_index] ? 1'b1 : 1'b0;
                    PE_number_en = (~last_PE && ready_ifmap_bufs[PE_index]) ? 1'b1 : 1'b0;
                    PE_number_clr = (last_PE && ready_ifmap_bufs[PE_index]) ? 1'b1 : 1'b0;
                    for (i = 0; i < N; i = i + 1) begin
                        change_modes[i] = can_start ? 1'b1 : 1'b0;
                    end
            end
            s6: begin 
                    PE_number_clr = 1'b1;
                    for (j = 0; j < N; j = j + 1) begin
                        change_modes[j] = 1'b1;
                    end
                end
            s7:  {change_modes[PE_index], func} = 2'b11;
            s8: func = 1'b1;
            s9: read_en_bufs[PE_index] = 1'b1;
            s10: begin
                    read_en_bufs[PE_index] = 1'b1;
                    write_en_psum_bufs[PE_index+1] = valids[PE_index] ? 1'b1 : 1'b0;
                    PE_number_en = ~valids[PE_index] ? 1'b1 : 1'b0;
            end
            s11: read_en_bufs[PE_index] = 1'b1;
            s12: begin 
                wen_global = valids[PE_index] ? 1'b1 : 1'b0;
                read_en_bufs[PE_index] = valids[PE_index] ? 1'b1 : 1'b0;
                write_addr_en = valids[PE_index] ? 1'b1 : 1'b0;
            end
            s13: finish = 1'b1;
        endcase     
    end

endmodule