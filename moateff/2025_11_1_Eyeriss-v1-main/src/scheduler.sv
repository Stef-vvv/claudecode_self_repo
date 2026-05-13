module scheduler #(
    parameter E_WIDTH = 6,
    parameter C_WIDTH = 10,
    parameter M_WIDTH = 10,
    parameter N_WIDTH = 3,
    
    parameter m_WIDTH = 6,
    parameter n_WIDTH = 3,
    parameter e_WIDTH = 6,
    parameter p_WIDTH = 5,
    parameter q_WIDTH = 3,
    parameter r_WIDTH = 2,
    parameter t_WIDTH = 3
) (
    input  logic clk,
    input  logic reset,    
    input  logic start,  
    output logic busy,
    output logic done,
    
    input  logic start_pass,
    output logic pass_done,    
    
    output logic start_noc,
    input  logic noc_done,
    
    output logic ofmap_dump,
    input  logic dump_done,
    output logic bias_sel,
    
    input  logic [E_WIDTH - 1:0] E,
    input  logic [C_WIDTH - 1:0] C,
    input  logic [M_WIDTH - 1:0] M,
    input  logic [N_WIDTH - 1:0] N,

    input  logic [m_WIDTH - 1:0] m,
    input  logic [n_WIDTH - 1:0] n,
    input  logic [e_WIDTH - 1:0] e,
    input  logic [p_WIDTH - 1:0] p,
    input  logic [q_WIDTH - 1:0] q, 
    input  logic [r_WIDTH - 1:0] r,
    input  logic [t_WIDTH - 1:0] t,

    output logic [M_WIDTH - 1:0] filter_ids         [0:1], 
    output logic [C_WIDTH - 1:0] filter_channel_ids [0:1],
    
    output logic [N_WIDTH - 1:0] ifmap_ids         [0:1], 
    output logic [C_WIDTH - 1:0] ifmap_channel_ids [0:1], 
    
    output logic [N_WIDTH - 1:0] psum_ids         [0:1], 
    output logic [M_WIDTH - 1:0] psum_channel_ids [0:1]
);

    typedef enum logic [3:0] {IDLE, CHECK, OUTER_LOOP, INNER_LOOP, START_PASS, PROCESS, PASS_DONE, DUMPING, DONE} state_type;
    state_type state_nxt, state_crnt;

    logic [C_WIDTH - 1:0] C_nxt, C_crnt;
    logic [M_WIDTH - 1:0] M_nxt, M_crnt;
    logic [N_WIDTH - 1:0] N_nxt, N_crnt; 
    logic [m_WIDTH - 1:0] m_nxt, m_crnt; 
    logic [E_WIDTH - 1:0] E_nxt, E_crnt; 
        
    logic [C_WIDTH - 1:0] channel_ids [0:1];
    
    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin 
            state_crnt <= IDLE;
            C_crnt <= 0;
            M_crnt <= 0;
            N_crnt <= 0;
            m_crnt <= 0;
            E_crnt <= 0; 
        end else begin
            state_crnt <= state_nxt;
            C_crnt <= C_nxt;
            M_crnt <= M_nxt;
            N_crnt <= N_nxt;
            m_crnt <= m_nxt;
            E_crnt <= E_nxt;
        end
    end
    
    always_comb begin
        start_noc = 1'b0;
        pass_done = 1'b0;
        busy = 1'b0;
        done = 1'b0;
        ofmap_dump = 1'b0;
        
        C_nxt = C_crnt;
        M_nxt = M_crnt;
        N_nxt = N_crnt;
        m_nxt = m_crnt;
        E_nxt = E_crnt;
        state_nxt = state_crnt;

        case(state_crnt)
            IDLE:
            begin
                if (start) begin 
                    state_nxt = CHECK; 
                end
            end
            CHECK:
            begin            
                if (start_pass) begin
                    state_nxt = START_PASS; 
                end
            end
            INNER_LOOP:
            begin
                if ((m_crnt + (p * t)) == m) begin 
                    m_nxt = 0;
                    if ((C_crnt + (q * r)) == C) begin 
                        C_nxt = 0;
                        state_nxt = DUMPING;
                    end else begin
                        C_nxt = C_crnt + (q * r);
                        state_nxt = CHECK;
                    end
                end else begin
                    m_nxt = m_crnt + (p * t);
                    state_nxt = CHECK;
                end
            end
            OUTER_LOOP:
            begin
                if (M_crnt + m == M) begin 
                    M_nxt = 0;
                    if (E_crnt + e >= E) begin
                        E_nxt = 0;
                        if ((N_crnt + n) == N) begin
                            N_nxt = 0;
                            state_nxt = DONE;
                        end else begin
                            N_nxt = N_crnt + n;
                            state_nxt = CHECK;
                        end
                    end else begin
                        E_nxt = E_crnt + e;
                        state_nxt = CHECK;
                    end
                end else begin
                    M_nxt = M_crnt + m;
                    state_nxt = CHECK;
                end
            end
            START_PASS:
            begin
                state_nxt = PROCESS;
                start_noc = 1'b1;
            end
            PROCESS:
            begin
                if (noc_done) begin 
                    state_nxt = PASS_DONE; 
                end
                busy = 1'b1;
            end
            PASS_DONE:
            begin
                state_nxt = INNER_LOOP;
                pass_done = 1'b1;
            end
            DUMPING:
            begin
                ofmap_dump = 1'b1;
                if (dump_done) begin 
                    state_nxt = OUTER_LOOP;
                end
            end
            DONE:
            begin
                state_nxt = IDLE;
                done = 1'b1;
            end
        endcase
    end
    
    always_comb begin
        if ((state_crnt == IDLE) || (state_crnt == DONE)) begin
            filter_ids = '{0, 0};
            channel_ids = '{0, 0};
            ifmap_ids = '{0, 0};
            
            bias_sel = 1'b0;
        end else if (state_crnt == DUMPING) begin
            filter_ids = '{M_crnt + 1, M_crnt + m};
            channel_ids = '{1, C};
            ifmap_ids = '{N_crnt + 1, N_crnt + n};
            
            bias_sel = 1'b0;
        end else begin
            filter_ids = '{M_crnt + m_crnt + 1, M_crnt + m_crnt + (p * t)};
            channel_ids = '{C_crnt + 1, C_crnt + (q * r)};
            ifmap_ids = '{N_crnt + 1, N_crnt + n};
            
            bias_sel = (channel_ids[0] == 0);
        end
    end

    assign filter_channel_ids = channel_ids;
    assign ifmap_channel_ids = channel_ids;
    
    assign psum_ids = ifmap_ids;
    assign psum_channel_ids = filter_ids;
        
endmodule
