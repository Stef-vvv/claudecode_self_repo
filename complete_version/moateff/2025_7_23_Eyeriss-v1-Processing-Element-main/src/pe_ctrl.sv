module pe_ctrl
#(
    parameter F_WIDTH = 6,
    parameter S_WIDTH = 4,
    parameter U_WIDTH = 3,    
    parameter n_WIDTH = 3,
    parameter p_WIDTH = 5,
    parameter q_WIDTH = 3,
    parameter V_WIDTH = 2,
    
    parameter IFMAP_ADDR_WIDTH  = 4,
    parameter FILTER_ADDR_WIDTH = 8,
    parameter PSUM_ADDR_WIDTH   = 5
) (
    input wire clk,                
    input wire reset,     
    input wire start,
    input wire await,
    output reg busy,
    
    input wire [S_WIDTH - 1:0] S, 
    input wire [F_WIDTH - 1:0] F,
    input wire [U_WIDTH - 1:0] U,
    input wire [n_WIDTH - 1:0] n,    
    input wire [p_WIDTH - 1:0] p,      
    input wire [q_WIDTH - 1:0] q, 
    input wire [V_WIDTH - 1:0] V,

    input wire ipsum_fifo_empty,
    input wire opsum_fifo_full,
    
    output reg reset_accumulation,   
    output reg accumulate_ipsum,
    output reg reset_ifmap_spad,
    output reg reset_filter_spad,
    
    // Addresses to access Spads
    output wire [IFMAP_ADDR_WIDTH  - 1:0] ifmap_addr,
    output wire [FILTER_ADDR_WIDTH - 1:0] filter_addr,
    output wire [PSUM_ADDR_WIDTH   - 1:0] psum_addr,
        
    output reg shift,          
    output reg rd_data, 
    output reg wr_psum,
    output reg pad
);
    
    // State encoding
    typedef enum logic [2:0] {IDLE, PROCESS, ACCUMULATE, STRIDE, PADDING, LOAD} state_t;
    state_t state_crnt, state_nxt;   
             
    reg [IFMAP_ADDR_WIDTH  - 1:0] i_crnt, i_nxt;
    reg [PSUM_ADDR_WIDTH   - 1:0] j_crnt, j_nxt;
       
    reg [F_WIDTH - 1:0] F_crnt, F_nxt;
    reg [n_WIDTH - 1:0] n_crnt, n_nxt;
    reg [V_WIDTH - 1:0] V_crnt, V_nxt;
    reg [U_WIDTH + q_WIDTH - 1:0] U_crnt, U_nxt;
            
    // State Transition Logic
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            i_crnt <= 'b0;
            j_crnt <= 'b0;
            F_crnt <= 'b0;
            U_crnt <= 'b0;
            n_crnt <= 'b0;
            V_crnt <= 'b0;
        end else begin
            state_crnt <= state_nxt;
            i_crnt <= i_nxt;
            j_crnt <= j_nxt;
            F_crnt <= F_nxt;
            U_crnt <= U_nxt;
            n_crnt <= n_nxt;
            V_crnt <= V_nxt;
        end
    end
    

    // State Output and Next State Logic
    always @(*) begin
        // Default assignments
        busy    = 1'b1;
        shift   = 1'b0;
        rd_data = 1'b0;
        wr_psum = 1'b0;
        pad     = 1'b0;
                
        reset_accumulation = 1'b0;
        accumulate_ipsum   = 1'b0;
                            
        state_nxt = state_crnt;
        i_nxt = i_crnt;
        j_nxt = j_crnt;
        F_nxt = F_crnt;
        U_nxt = U_crnt;
        n_nxt = n_crnt;
        V_nxt = V_crnt;
                
        reset_ifmap_spad  = 1'b0;
        reset_filter_spad = 1'b0;
                               
        case (state_crnt)
            IDLE: begin
                busy = 1'b0;                
                if (start) begin
                    state_nxt = PROCESS;
                end 
            end
            PROCESS: begin
                if (~await) begin
                    reset_accumulation = (i_crnt == 'b0) ? 1'b1 : 1'b0;
                    rd_data = 1'b1;
                    wr_psum = 1'b1;
                    if (j_crnt == (p - 1)) begin 
                        if (i_crnt == (S * q - 1)) begin 
                            i_nxt = 'b0;
                            j_nxt = 'b0;
                            state_nxt = ACCUMULATE;
                        end else begin
                            i_nxt = i_crnt + 1;
                            j_nxt = 'b0;
                        end
                    end else begin
                        j_nxt = j_crnt + 1; 
                    end
                end
            end
            ACCUMULATE: begin
                if ((~ipsum_fifo_empty) & (~opsum_fifo_full)) begin
                    accumulate_ipsum = 1'b1;
                    if (j_crnt == (p - 1)) begin
                        j_nxt = 'b0;
                        if (F_crnt == (F - 1)) begin
                            F_nxt = 'b0;
                            V_nxt = V;
                            state_nxt = PADDING;
                        end else begin
                            F_nxt = F_crnt + 1;
                            state_nxt = STRIDE;
                        end
                    end else begin
                        j_nxt = j_crnt + 1;
                    end
                end
            end
            STRIDE: begin
                shift = 1'b1; 
                if (U_crnt == (U * q) - 1) begin
                    U_nxt = 'b0;
                    state_nxt = PROCESS;
                end else begin
                    U_nxt = U_crnt + 1;
                end
            end
            PADDING: begin
                if (V_crnt == 2'b00) begin
                    V_nxt = 'b0;
                    state_nxt = LOAD;
                end else begin
                    pad = 1'b1;
                    V_nxt = V_crnt + 1;
                end
            end
            LOAD: begin
                reset_ifmap_spad = 1'b1; 
                if (n_crnt == (n - 1)) begin
                    n_nxt = 'b0;
                    reset_filter_spad = 1'b1;
                    state_nxt = IDLE;
                end else begin
                    n_nxt = n_crnt + 1;
                    state_nxt = PROCESS;
                end
            end
            default: begin
                state_nxt = IDLE;
            end
        endcase
    end
    
    assign ifmap_addr  = i_crnt;
    assign filter_addr = i_crnt * p + j_crnt;
    assign psum_addr   = j_crnt;
     
endmodule
