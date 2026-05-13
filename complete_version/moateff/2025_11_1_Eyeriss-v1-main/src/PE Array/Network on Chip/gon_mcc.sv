module gon_mcc #(
    parameter int DATA_WIDTH = 64, 
    parameter int TAG_WIDTH = 4
) (
    input logic [DATA_WIDTH - 1:0] data_in,
    input logic [TAG_WIDTH - 1:0] tag,
    input logic ready_in, clk, reset, enable_in,
    input logic scan_en_id, scan_in_id,

    output logic [DATA_WIDTH - 1:0] data_out,
    output logic ready_out, enable_out,
    output logic scan_out_id
);

    logic equal_tag, enable_mid;
    logic [TAG_WIDTH - 1:0] q_id;
    
    assign equal_tag = (q_id == tag);
    assign ready_out = ready_in | (!equal_tag);
    assign enable_mid = enable_in & ready_in & equal_tag;
    assign enable_out = enable_mid;
    assign data_out = enable_mid ? data_in : {DATA_WIDTH{1'bz}};
    
    scan_ff_Nbit #(.DATA_WIDTH(TAG_WIDTH)) scan_ff_Nbit_inst (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en_id),
        .scan_in(scan_in_id),
        .q(q_id),
        .scan_out(scan_out_id)
    );

endmodule