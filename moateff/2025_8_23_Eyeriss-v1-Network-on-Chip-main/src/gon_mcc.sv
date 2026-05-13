module gon_mcc #(
    parameter DATA_WIDTH = 64, 
    parameter TAG_WIDTH = 4
)(
    input wire clk, reset,
    input wire [TAG_WIDTH-1:0] id,
    input wire [TAG_WIDTH-1:0] tag,
    input wire [DATA_WIDTH-1:0] data_in,
    input wire ready_in, enable_in,

    output wire [DATA_WIDTH-1:0] data_out,
    output wire enable_out, ready_out
);

    // Internal signals
    wire equal_tag, enable_mid;
    reg [TAG_WIDTH-1:0] q_id;
    
    // Combinational logic
    assign equal_tag = (q_id == tag);
    assign ready_out = ready_in | (!equal_tag);
    assign enable_mid = enable_in & ready_in & equal_tag;
    assign enable_out = enable_mid;
    assign data_out = enable_mid ? data_in : {DATA_WIDTH{1'bz}};
    
    always @(negedge clk or posedge reset) begin
        if (reset) begin
            q_id <= {TAG_WIDTH{1'b1}}; 
        end else begin
            q_id <= id; 
        end
    end

endmodule