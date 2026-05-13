module psum_tag_generator
#( 
    parameter t_WIDTH = 3,
    parameter e_WIDTH = 6,
    parameter ROW_TAG_WIDTH = 4,
    parameter COL_TAG_WIDTH = 4
) (
    input clk,
    input reset,
    input start,
    input enable,
    output reg busy,
    
    input [e_WIDTH - 1:0] e, 
    input [t_WIDTH - 1:0] t,

    output reg [ROW_TAG_WIDTH - 1:0] row_tag,
    output reg [COL_TAG_WIDTH - 1:0] col_tag
);

    typedef enum {IDLE, LOOPING} state_type;
    state_type state_nxt, state_crnt;
    
    logic [COL_TAG_WIDTH - 1:0] col_crnt, col_nxt; 
    logic [ROW_TAG_WIDTH - 1:0] row_crnt, row_nxt;
    logic [t_WIDTH + e_WIDTH - 1 : 0] counter_crnt, counter_nxt;
    
    logic [t_WIDTH + e_WIDTH - 5 : 0] num_of_rows;
    logic [3 : 0] num_of_cols ;
    
    assign num_of_rows = (e * t + 13) >> 4;
    assign num_of_cols = 14;
    
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            state_crnt <= IDLE;
            col_crnt <= 0;
            row_crnt <= 0;
            counter_crnt <= 0;
        end else begin
            state_crnt <= state_nxt;
            col_crnt <= col_nxt;
            row_crnt <= row_nxt;
            counter_crnt <= counter_nxt;
        end
    end

    always @(*) begin
        // Default assignments
        busy = 1'b0;    
        state_nxt = state_crnt;
        col_nxt = col_crnt;
        row_nxt = row_crnt;
        counter_nxt = counter_crnt;
            
        case (state_crnt)
            IDLE: 
            begin
                col_nxt = 0;
                row_nxt = 0;
                counter_nxt = 0;
                if (start) begin
                    state_nxt = LOOPING;
                end
            end
            LOOPING: 
            begin
                if (enable) begin
                    busy = 1'b1;
                    if (counter_crnt == ((e*t)-1))begin
                         col_nxt = 0;
                         row_nxt = 0;
                         counter_nxt = 0;
                    end else if (e<14) begin
                        counter_nxt = counter_crnt + 1;
                        if (row_crnt == num_of_rows - 1) begin
                            if (col_crnt == num_of_cols - 1) begin
                                 col_nxt = 0;
                                 row_nxt = 0;
                                 counter_nxt = 0;
                            end else begin
                                col_nxt = col_crnt + 1;
                                row_nxt = 0;
                            end
                        end else begin
                            row_nxt = row_crnt + 1;
                        end
                    end else begin
                        counter_nxt = counter_crnt + 1;
                        if (col_crnt == num_of_cols - 1) begin
                            if (row_crnt == num_of_rows - 1) begin
                                col_nxt = 0;
                                row_nxt = 0;
                                counter_nxt = 0;
                            end else begin
                                row_nxt = row_crnt + 1;
                                col_nxt = 0;
                            end
                        end else begin
                            col_nxt = col_crnt + 1;
                        end
                    end
                end
            end 
            default: state_nxt = IDLE;  
        endcase
    end

    always @(*) begin
         col_tag = col_crnt;
         row_tag = row_crnt;
    end

endmodule
