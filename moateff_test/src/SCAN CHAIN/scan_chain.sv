module scan_chain #(
    parameter H_WIDTH = 8,
    parameter W_WIDTH = 8,
    parameter R_WIDTH = 4,
    parameter S_WIDTH = 4,
    parameter E_WIDTH = 6,
    parameter F_WIDTH = 6,

    parameter C_WIDTH = 10,
    parameter M_WIDTH = 10,
    parameter N_WIDTH = 3,
    parameter U_WIDTH = 3,
    
    parameter m_WIDTH = 8,
    parameter n_WIDTH = 3,
    parameter e_WIDTH = 6,
    parameter p_WIDTH = 5,
    parameter q_WIDTH = 3,
    parameter r_WIDTH = 2,
    parameter t_WIDTH = 3
)(
    input  wire clk,
    input  wire reset,
    input  wire scan_en,
    input  wire scan_in,
    output wire scan_out,

    output  logic  [H_WIDTH - 1:0] H,
    output  logic  [W_WIDTH - 1:0] W,
    output  logic  [R_WIDTH - 1:0] R,
    output  logic  [S_WIDTH - 1:0] S,
    output  logic  [E_WIDTH - 1:0] E,
    output  logic  [F_WIDTH - 1:0] F,

    output  logic  [C_WIDTH - 1:0] C,
    output  logic  [M_WIDTH - 1:0] M,
    output  logic  [N_WIDTH - 1:0] N,
    output  logic  [U_WIDTH - 1:0] U,

    output  logic  [m_WIDTH - 1:0] m,
    output  logic  [n_WIDTH - 1:0] n,
    output  logic  [e_WIDTH - 1:0] e,
    output  logic  [p_WIDTH - 1:0] p,
    output  logic  [q_WIDTH - 1:0] q,
    output  logic  [r_WIDTH - 1:0] r,
    output  logic  [t_WIDTH - 1:0] t
);

    logic [0:15] scan_w;

    scan_ff_Nbit #(.DATA_WIDTH(H_WIDTH)) H_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_in),
        .q(H),
        .scan_out(scan_w[0])
    );
    
    scan_ff_Nbit #(.DATA_WIDTH(W_WIDTH)) W_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[0]),
        .q(W),
        .scan_out(scan_w[1])
    );
   
   scan_ff_Nbit #(.DATA_WIDTH(R_WIDTH)) R_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[1]),
        .q(R),
        .scan_out(scan_w[2])
    );
    
   scan_ff_Nbit #(.DATA_WIDTH(S_WIDTH)) S_reg (
         .clk(clk),
         .reset(reset),
         .scan_en(scan_en),
         .scan_in(scan_w[2]),
         .q(S),
         .scan_out(scan_w[3])
    );
     
    scan_ff_Nbit #(.DATA_WIDTH(E_WIDTH)) E_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[3]),
        .q(E),
        .scan_out(scan_w[4])
    );
    
    scan_ff_Nbit #(.DATA_WIDTH(F_WIDTH)) F_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[4]),
        .q(F),
        .scan_out(scan_w[5])
    );

    scan_ff_Nbit #(.DATA_WIDTH(C_WIDTH)) C_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[5]),
        .q(C),
        .scan_out(scan_w[6])
    );

    scan_ff_Nbit #(.DATA_WIDTH(M_WIDTH)) M_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[6]),
        .q(M),
        .scan_out(scan_w[7])
    );

    scan_ff_Nbit #(.DATA_WIDTH(N_WIDTH)) N_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[7]),
        .q(N),
        .scan_out(scan_w[8])
    );

    scan_ff_Nbit #(.DATA_WIDTH(U_WIDTH)) U_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[8]),
        .q(U),
        .scan_out(scan_w[9])
    );
    scan_ff_Nbit #(.DATA_WIDTH(m_WIDTH)) m_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[9]),
        .q(m),
        .scan_out(scan_w[10])
    );

    scan_ff_Nbit #(.DATA_WIDTH(n_WIDTH)) n_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[10]),
        .q(n),
        .scan_out(scan_w[11])
    );

    scan_ff_Nbit #(.DATA_WIDTH(e_WIDTH)) e_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[11]),
        .q(e),
        .scan_out(scan_w[12])
    );

    scan_ff_Nbit #(.DATA_WIDTH(p_WIDTH)) p_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[12]),
        .q(p),
        .scan_out(scan_w[13])
    );

    scan_ff_Nbit #(.DATA_WIDTH(q_WIDTH)) q_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[13]),
        .q(q),
        .scan_out(scan_w[14])
    );

    scan_ff_Nbit #(.DATA_WIDTH(r_WIDTH)) r_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[14]),
        .q(r),
        .scan_out(scan_w[15])
    );

    scan_ff_Nbit #(.DATA_WIDTH(t_WIDTH)) t_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[15]),
        .q(t),
        .scan_out(scan_out)
    );
    
endmodule
