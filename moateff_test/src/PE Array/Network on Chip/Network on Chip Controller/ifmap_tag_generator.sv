module ifmap_tag_generator
#( 
    parameter D_WIDTH = 8,
    parameter U_WIDTH = 3,
    parameter r_WIDTH = 2,
    parameter ROW_TAG_WIDTH = 4,
    parameter COL_TAG_WIDTH = 5
) (
    input clk,
    input reset,
    input start,
    input enable,

    input [D_WIDTH - 1:0] D,
    input [U_WIDTH - 1:0] U,
    input [r_WIDTH - 1:0] r,

    output reg [ROW_TAG_WIDTH - 1:0] row_tag,
    output reg [COL_TAG_WIDTH - 1:0] col_tag
);

    typedef enum {IDLE, LOOPING} state_type;
    state_type state_nxt, state_crnt;

    logic [COL_TAG_WIDTH - 1:0] max_col_id;
    assign max_col_id = D >> (U >> 1);
        
    logic [D_WIDTH - 1:0] D_crnt, D_nxt;
    logic [U_WIDTH - 1:0] U_crnt, U_nxt;
    logic [r_WIDTH - 1:0] r_crnt, r_nxt;
    logic [COL_TAG_WIDTH - 1:0] col_crnt, col_nxt;
    
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            r_crnt <= 0;
            D_crnt <= 0;
            U_crnt <= 0;
            col_crnt <= 0;
        end else begin
            state_crnt <= state_nxt;
            r_crnt <= r_nxt;
            D_crnt <= D_nxt;
            U_crnt <= U_nxt;
            col_crnt <= col_nxt;   
        end
    end

    always @(*) begin 
        // Default assignments    
        state_nxt = state_crnt;        
        r_nxt = r_crnt;
        D_nxt = D_crnt;
        U_nxt = U_crnt;
        col_nxt = col_crnt;
         
        case (state_crnt)
            IDLE: 
            begin
                col_nxt = 0;
                U_nxt = 0;
                r_nxt = 0;
                D_nxt = 0;
                
                if (start) begin
                    state_nxt = LOOPING;
                end
            end
            LOOPING: 
            begin
                if (enable) begin
                    if (D_crnt == (r * D) - 1) begin
                        col_nxt = 0;
                        U_nxt = 0;
                        r_nxt = 0;
                        D_nxt = 0;
                    end else begin
                        D_nxt = D_crnt + 1;
                        if (r_crnt == r - 1) begin
                            if (U_crnt == U - 1) begin
                                if (col_crnt == max_col_id) begin
                                    col_nxt = 0;
                                    U_nxt = 0;
                                    r_nxt = 0;
                                end else begin
                                    col_nxt = col_crnt + 1;
                                    U_nxt = 0;
                                    r_nxt = 0; 
                                end
                            end else begin
                                U_nxt = U_crnt + 1;
                                r_nxt = 0;
                            end
                        end else begin
                            r_nxt = r_crnt + 1;
                        end
                    end
                end
            end
            default: state_nxt = IDLE;
        endcase
    end

    always @(*) begin
        col_tag = col_crnt;
        row_tag = U_crnt + (r_crnt * 4);
    end

endmodule

