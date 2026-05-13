module filter_tag_generator
#( 
    parameter R_WIDTH = 4,
    parameter r_WIDTH = 2,
    parameter t_WIDTH = 3,
    parameter ROW_TAG_WIDTH = 4,
    parameter COL_TAG_WIDTH = 4
) (
    input clk,
    input reset,
    input start,
    input enable,
    
    input [R_WIDTH - 1:0] R, 
    input [r_WIDTH - 1:0] r,  
    input [t_WIDTH - 1:0] t, 

    output reg [ROW_TAG_WIDTH - 1:0] row_tag,
    output reg [COL_TAG_WIDTH - 1:0] col_tag
);

    typedef enum {IDLE, LOOPING} state_type;
    state_type state_nxt, state_crnt;
    
    logic [R_WIDTH - 1:0] R_crnt, R_nxt;
    logic [r_WIDTH - 1:0] r_crnt, r_nxt;  
    logic [t_WIDTH - 1:0] t_crnt, t_nxt; 

    always @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            R_crnt <= 0;
            r_crnt <= 0;
            t_crnt <= 0;
        end else begin
            state_crnt <= state_nxt;
            R_crnt <= R_nxt;
            r_crnt <= r_nxt;
            t_crnt <= t_nxt;
        end
    end

    always @(*) begin
        // Default assignments    
        state_nxt = state_crnt;
        R_nxt = R_crnt;
        r_nxt = r_crnt;
        t_nxt = t_crnt;
            
        case (state_crnt)
            IDLE: 
            begin
                R_nxt = 0;
                r_nxt = 0;
                t_nxt = 0;
                if (start) begin
                    state_nxt = LOOPING;
                end
            end
            LOOPING: 
            begin
                if (enable) begin
                    if (t_crnt == t - 1) begin
                        if (r_crnt == r - 1) begin
                            if (R_crnt == R - 1) begin
                                R_nxt = 0;
                                t_nxt = 0;
                                r_nxt = 0; 
                            end else begin
                                R_nxt = R_crnt + 1;
                                t_nxt = 0;
                                r_nxt = 0; 
                            end
                        end else begin
                            r_nxt = r_crnt + 1;
                            t_nxt = 0;
                        end
                    end else begin
                        t_nxt = t_crnt + 1;
                    end
                end
            end 
            default: state_nxt = IDLE;  
        endcase
    end

    always @(*) begin
         col_tag = t_crnt + r_crnt * 2;
         row_tag = R_crnt;
    end

endmodule
