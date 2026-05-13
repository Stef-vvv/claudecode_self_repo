module ifmap_index_generator
#( 
    parameter D_WIDTH = 8,
    parameter W_WIDTH = 8,
    parameter n_WIDTH = 3,
    parameter q_WIDTH = 3,
    parameter r_WIDTH = 2
) (
    input clk,
    input reset,
    input start,
    input await,
    
    output reg busy,
    output reg done,

    input [D_WIDTH - 1:0] D,
    input [W_WIDTH - 1:0] W,
    input [n_WIDTH - 1:0] n,
    input [q_WIDTH - 1:0] q,
    input [r_WIDTH - 1:0] r,

    output reg [n_WIDTH - 1:0] ifmap_index,
    output reg [q_WIDTH + r_WIDTH - 1:0] channel_index,
    output reg [D_WIDTH - 1:0] row_index,
    output reg [W_WIDTH - 1:0] col_index    
);
    
    typedef enum {IDLE, LOOPING, OUTER_LOOP, INNER_LOOP, DONE} state_type;
    state_type state_nxt, state_crnt;
    
    logic [D_WIDTH - 1:0] D_nxt, D_crnt;
    logic [W_WIDTH - 1:0] W_nxt, W_crnt;
    logic [n_WIDTH - 1:0] n_nxt, n_crnt;
    logic [q_WIDTH - 1:0] q_nxt, q_crnt;
    logic [r_WIDTH - 1:0] r_nxt, r_crnt;
        
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            n_crnt <= 0;
            W_crnt <= 0;
            q_crnt <= 0;
            D_crnt <= 0;
            r_crnt <= 0;
        end else begin
            state_crnt <= state_nxt;
            n_crnt <= n_nxt;
            W_crnt <= W_nxt;
            q_crnt <= q_nxt;
            D_crnt <= D_nxt;
            r_crnt <= r_nxt;
        end
    end
    
    always @(*) begin
        // Default assignments
        busy = 1'b0;
        done = 1'b0;
        state_nxt = state_crnt;
        n_nxt = n_crnt;
        W_nxt = W_crnt;
        q_nxt = q_crnt;
        D_nxt = D_crnt;
        r_nxt = r_crnt;
        
        case(state_crnt)
            IDLE:
            begin
                if (start) begin
                    state_nxt = LOOPING;
                end 
            end
            LOOPING:
            begin
               if (!await) begin
                    busy = 1'b1;
                    if (r_crnt == r - 1) begin 
                        if (D_crnt == D - 1) begin 
                            if (q_crnt == q - 1) begin 
                                if (W_crnt == W - 1) begin
                                    if (n_crnt == n - 1) begin
                                        state_nxt = DONE;
                                        n_nxt = 0;
                                        W_nxt = 0;
                                        q_nxt = 0;
                                        D_nxt = 0;
                                        r_nxt = 0;
                                    end else begin
                                        n_nxt = n_crnt + 1;
                                        W_nxt = 0;
                                        q_nxt = 0;
                                        D_nxt = 0;
                                        r_nxt = 0;
                                    end
                                end else begin
                                    W_nxt = W_crnt + 1;
                                    q_nxt = 0;
                                    D_nxt = 0;
                                    r_nxt = 0;
                                end
                            end else begin
                                q_nxt = q_crnt + 1;
                                D_nxt = 0;
                                r_nxt = 0;
                            end
                        end else begin
                            D_nxt = D_crnt + 1;
                            r_nxt = 0;
                        end
                    end else begin
                        r_nxt = r_crnt + 1; 
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
        ifmap_index   = n_crnt;
        channel_index = q_crnt + r_crnt * q;
        row_index     = D_crnt;
        col_index     = W_crnt;
    end
        
endmodule
