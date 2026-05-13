module filter_index_generator
#( 
    parameter R_WIDTH = 4,
    parameter S_WIDTH = 6,
    parameter p_WIDTH = 5,
    parameter q_WIDTH = 3,
    parameter r_WIDTH = 2,
    parameter t_WIDTH = 3,
    parameter i_WIDTH = 3
) (
    input clk,
    input reset,
    input start,
    input await,
    
    output reg busy,
    output reg done,
    
    input [R_WIDTH - 1:0] R,
    input [S_WIDTH - 1:0] S,
    input [p_WIDTH - 1:0] p,
    input [q_WIDTH - 1:0] q,
    input [r_WIDTH - 1:0] r,
    input [t_WIDTH - 1:0] t, 

    output reg [p_WIDTH + t_WIDTH - 1:0] filter_index,
    output reg [q_WIDTH + r_WIDTH - 1:0] channel_index,
    output reg [R_WIDTH - 1:0] row_index,
    output reg [S_WIDTH - 1:0] col_index
);
    
    localparam i = 4;
    
    typedef enum {IDLE, OUTER_LOOP, INNER_LOOP, DONE} state_type;
    state_type state_nxt, state_crnt;
    
    logic [S_WIDTH - 1:0] S_nxt, S_crnt;
    logic [R_WIDTH - 1:0] R_nxt, R_crnt;
    logic [p_WIDTH - 1:0] p_nxt, p_crnt;
    logic [q_WIDTH - 1:0] q_nxt, q_crnt;
    logic [r_WIDTH - 1:0] r_nxt, r_crnt;
    logic [t_WIDTH - 1:0] t_nxt, t_crnt;
    logic [i_WIDTH - 1:0] i_nxt, i_crnt;
    
    logic [S_WIDTH - 1:0] S_reg_nxt, S_reg_crnt;
    logic [p_WIDTH - 1:0] p_reg_nxt, p_reg_crnt;
    logic [q_WIDTH - 1:0] q_reg_nxt, q_reg_crnt;
    
    logic lock_nxt, lock_crnt;
        
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            S_crnt <= 0;
            R_crnt <= 0;
            p_crnt <= 0;
            q_crnt <= 0;
            r_crnt <= 0;
            t_crnt <= 0;
            i_crnt <= 0;
            
            S_reg_crnt <= 0;
            p_reg_crnt <= 0;
            q_reg_crnt <= 0;
            
            lock_crnt <= 1;
        end else begin
            state_crnt <= state_nxt;
            S_crnt <= S_nxt;
            R_crnt <= R_nxt;
            p_crnt <= p_nxt;
            q_crnt <= q_nxt;
            r_crnt <= r_nxt;
            t_crnt <= t_nxt;
            i_crnt <= i_nxt;
            
            S_reg_crnt <= S_reg_nxt;
            p_reg_crnt <= p_reg_nxt;
            q_reg_crnt <= q_reg_nxt;
            
            lock_crnt <= lock_nxt;
        end
    end
    
    always @(*) begin
        // Default assignments
        busy = 1'b0;
        done = 1'b0;
        state_nxt = state_crnt;
        S_nxt = S_crnt;
        R_nxt = R_crnt;
        p_nxt = p_crnt;
        q_nxt = q_crnt;
        r_nxt = r_crnt;
        t_nxt = t_crnt;
        i_nxt = i_crnt;
        
        S_reg_nxt = S_reg_crnt;
        p_reg_nxt = p_reg_crnt;
        q_reg_nxt = q_reg_crnt;
        
        lock_nxt = lock_crnt;                                
        case(state_crnt)
            IDLE:
            begin
                if (start) begin
                    state_nxt = INNER_LOOP;
                end 
            end
            OUTER_LOOP:
            begin
                lock_nxt = 1'b1;
                if (t_crnt == t - 1) begin
                    if (r_crnt == r - 1) begin
                        if (R_crnt == R - 1) begin
                            R_nxt = 0;
                            r_nxt = 0;
                            t_nxt = 0;
                            if (!lock_crnt) begin
                                state_nxt = DONE;
                            end else begin
                                state_nxt = INNER_LOOP;
                            end
                            p_reg_nxt = p_crnt;	
                            q_reg_nxt = q_crnt; 
                            S_reg_nxt = S_crnt;
                        end else begin
                            R_nxt = R_crnt + 1;
                            r_nxt = 0;
                            t_nxt = 0;
                            state_nxt = INNER_LOOP;
                            p_nxt = p_reg_crnt;	
                            q_nxt = q_reg_crnt; 
                            S_nxt = S_reg_crnt;
                        end
                    end else begin
                        r_nxt = r_crnt + 1;
                        t_nxt = 0;
                        state_nxt = INNER_LOOP;
                        p_nxt = p_reg_crnt;	
                        q_nxt = q_reg_crnt; 
                        S_nxt = S_reg_crnt;
                    end
                end else begin
                    t_nxt = t_crnt + 1;
                    state_nxt = INNER_LOOP;
                    p_nxt = p_reg_crnt;	
                    q_nxt = q_reg_crnt; 
                    S_nxt = S_reg_crnt;
                end
            end
            INNER_LOOP:
            begin
                if (!await) begin 
                    busy = 1'b1;  
                    if (i_crnt == i - 1) begin
                        i_nxt = 0;
                        state_nxt = OUTER_LOOP;
                    end else begin
                        i_nxt = i_crnt + 1;
                    end
                    
                    if (lock_crnt) begin
                        if (p_crnt == p - 1) begin
                            p_nxt = 0;
                            if (q_crnt == q - 1) begin
                                q_nxt = 0;
                                if (S_crnt == S - 1) begin
                                    lock_nxt = 1'b0;
                                    S_nxt = 0;
                                end else begin 
                                    S_nxt = S_crnt + 1;
                                end
                            end else begin 
                                q_nxt = q_crnt + 1;
                            end
                        end else begin 
                            p_nxt = p_crnt + 1;
                        end
                     end
                end
            end
            DONE:
            begin
                done = 1'b1;
                state_nxt = IDLE;
            end
            default: state_nxt = IDLE;
        endcase
    end

    always @(*) begin
        filter_index  = p_crnt + (t_crnt * p);
        channel_index = q_crnt + (r_crnt * q);
        row_index     = R_crnt;
        col_index     = S_crnt;
    end
    
endmodule
