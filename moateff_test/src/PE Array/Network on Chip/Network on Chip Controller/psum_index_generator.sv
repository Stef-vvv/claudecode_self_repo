module psum_index_generator
#( 
    parameter F_WIDTH = 6,
    parameter m_WIDTH = 8,
    parameter n_WIDTH = 3,
    parameter e_WIDTH = 8,
    parameter p_WIDTH = 5,
    parameter t_WIDTH = 3,
    parameter i_WIDTH = 3
) (
    input clk,
    input reset,
    input start,
    input await,
    
    output reg busy,
    output reg done,
    
    input [F_WIDTH - 1:0] F,
    input [m_WIDTH - 1:0] m,
    input [n_WIDTH - 1:0] n,
    input [e_WIDTH - 1:0] e,
    input [p_WIDTH - 1:0] p,
    input [t_WIDTH - 1:0] t,

    output reg [n_WIDTH - 1:0] psum_index,
    output reg [m_WIDTH - 1:0] channel_index,
    output reg [e_WIDTH - 1:0] row_index,
    output reg [F_WIDTH - 1:0] col_index
);
    
    localparam i = 4;
    
	typedef enum {IDLE, OUTER_LOOP, INNER_LOOP, DONE} state_type;
    state_type state_nxt, state_crnt;
	
	logic [F_WIDTH - 1:0] F_nxt, F_crnt;
    logic [m_WIDTH - 1:0] m_nxt, m_crnt;
    logic [n_WIDTH - 1:0] n_nxt, n_crnt;
    logic [e_WIDTH - 1:0] e_nxt, e_crnt;
    logic [p_WIDTH - 1:0] p_nxt, p_crnt;
    logic [t_WIDTH - 1:0] t_nxt, t_crnt;
    logic [i_WIDTH - 1:0] i_nxt, i_crnt;
	
    logic [F_WIDTH - 1:0] F_reg_nxt, F_reg_crnt;
    logic [n_WIDTH - 1:0] n_reg_nxt, n_reg_crnt;
    logic [p_WIDTH - 1:0] p_reg_nxt, p_reg_crnt;
    
    logic lock_nxt, lock_crnt;

	always @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            F_crnt <= 0;
            m_crnt <= 0;
            n_crnt <= 0;
            e_crnt <= 0;
            p_crnt <= 0;
            t_crnt <= 0;
            i_crnt <= 0;
            
            F_reg_crnt <= 0;
            n_reg_crnt <= 0;
            p_reg_crnt <= 0;
                        
            lock_crnt <= 1;
        end else begin
            state_crnt <= state_nxt;
            F_crnt <= F_nxt;
            m_crnt <= m_nxt;
            n_crnt <= n_nxt;
            e_crnt <= e_nxt;
            p_crnt <= p_nxt;
            t_crnt <= t_nxt;
            i_crnt <= i_nxt;
            
            F_reg_crnt <= F_reg_nxt;
            n_reg_crnt <= n_reg_nxt;
            p_reg_crnt <= p_reg_nxt;
            
            lock_crnt <= lock_nxt;            
        end
    end
	
	always @(*) begin
        // Default assignments
        busy = 1'b0;
        done = 1'b0;
        state_nxt = state_crnt;
        F_nxt = F_crnt;
		m_nxt = m_crnt;
		n_nxt = n_crnt;
		e_nxt = e_crnt;
		p_nxt = p_crnt;
		t_nxt = t_crnt;
		i_nxt = i_crnt;
		
		F_reg_nxt = F_reg_crnt;
        n_reg_nxt = n_reg_crnt;
        p_reg_nxt = p_reg_crnt;
        
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
                    if (e_crnt == e - 1) begin
                        e_nxt = 0;
                        t_nxt = 0;
                        if (!lock_crnt) begin
                            state_nxt = DONE;
                        end else begin
                            state_nxt = INNER_LOOP;
                        end
                        F_reg_nxt = F_crnt;      
                        n_reg_nxt = n_crnt;
                        p_reg_nxt = p_crnt;
                    end else begin
                        e_nxt = e_crnt + 1;
                        t_nxt = 0;
                        state_nxt = INNER_LOOP;
                        F_nxt = F_reg_crnt;      
                        n_nxt = n_reg_crnt;
                        p_nxt = p_reg_crnt;
                    end
                end else begin
                    t_nxt = t_crnt + 1;
                    state_nxt = INNER_LOOP;
                    F_nxt = F_reg_crnt;      
                    n_nxt = n_reg_crnt;
                    p_nxt = p_reg_crnt;
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
                            if (F_crnt == F - 1) begin
                                F_nxt = 0;
                                if (n_crnt == n - 1) begin
                                    lock_nxt = 1'b0;
                                    n_nxt = 0;
                                end else begin 
                                    n_nxt = n_crnt + 1;
                                end
                            end else begin 
                                F_nxt = F_crnt + 1;
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
				if (m_crnt + (p * t) == m) begin
				    m_nxt = 0;
				end else begin
				    m_nxt = m_crnt + (p * t);
				end
                state_nxt = IDLE;
			end
			default: state_nxt = IDLE;
		endcase
	end	
	
	 always @(*) begin
        psum_index    = n_crnt;
        channel_index = m_crnt + p_crnt + (t_crnt * p);
        row_index     = e_crnt;
        col_index     = F_crnt;
    end
	
endmodule
