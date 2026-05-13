module pe
#(
    parameter DATA_WIDTH = 16,
    
    parameter W_WIDTH = 8,
    parameter S_WIDTH = 5,
    parameter F_WIDTH = 6,
    parameter U_WIDTH = 3,
    parameter n_WIDTH = 3,
    parameter p_WIDTH = 5,
    parameter q_WIDTH = 3,
    
    parameter V_WIDTH = 2,
    
    parameter IFMAP_SPAD_DEPTH  = 12,
    parameter FILTER_SPAD_DEPTH = 224,
    parameter PSUM_SPAD_DEPTH   = 24
) (
    input  clk,
    input  reset,
    output busy, 
            
    input [W_WIDTH - 1:0] W,    
    input [S_WIDTH - 1:0] S,    
    input [F_WIDTH - 1:0] F,
    input [U_WIDTH - 1:0] U,
    input [n_WIDTH - 1:0] n,    
    input [p_WIDTH - 1:0] p,      
    input [q_WIDTH - 1:0] q, 

    // Input Data Interface
    input  [DATA_WIDTH - 1:0] ifmap_pixel,      
    input                     wr_ifmap,
    output                    ifmap_spad_full,

    input  [DATA_WIDTH - 1:0] filter_pixel,              
    input                     wr_filter,
    output                    filter_spad_full,

    input  [DATA_WIDTH - 1:0] ipsum_pixel,       
    output                    pop_ipsum,      
    input                     ipsum_fifo_empty,
        
    // Output Data Interface
    output [DATA_WIDTH - 1:0] opsum_pixel,       
    output                    push_opsum,    
    input                     opsum_fifo_full
);
    
    localparam IFMAP_ADDR_WIDTH  = $clog2(IFMAP_SPAD_DEPTH);
    localparam FILTER_ADDR_WIDTH = $clog2(FILTER_SPAD_DEPTH);
    localparam PSUM_ADDR_WIDTH   = $clog2(PSUM_SPAD_DEPTH);
     
    wire [V_WIDTH - 1:0] V; 
    
    wire filter_spad_empty;
    wire ifmap_spad_empty;
    
    wire [DATA_WIDTH - 1:0] ifmap_from_spad;
    wire [DATA_WIDTH - 1:0] filter_from_spad;
    wire [DATA_WIDTH - 1:0] pusm_from_spad, pusm_from_spad_w;
    
    wire [IFMAP_ADDR_WIDTH  - 1:0] ifmap_addr;
    wire [FILTER_ADDR_WIDTH - 1:0] filter_addr;
    wire [PSUM_ADDR_WIDTH   - 1:0] psum_addr, psum_addr_r, psum_addr_rr;
    
    wire [DATA_WIDTH - 1:0] adder_in1;
    wire [DATA_WIDTH - 1:0] adder_in2;
    wire [DATA_WIDTH - 1:0] sum_result;
    
    wire [DATA_WIDTH - 1:0] mux1_out;
    wire [DATA_WIDTH - 1:0] mux1_out_r;
    wire [DATA_WIDTH - 1:0] mux2_out;
    
    wire [DATA_WIDTH - 1:0]       mul_in1;
    wire [DATA_WIDTH - 1:0]       mul_in2;
    wire [(2 * DATA_WIDTH) - 1:0] mul_result;
    
    wire [DATA_WIDTH - 1:0] truncated_result;
    
    wire accumulate_ipsum, accumulate_ipsum_r, accumulate_ipsum_rr;
    wire reset_accumulation, reset_accumulation_r;
    
    wire reset_ifmap_spad;
    wire reset_filter_spad;
    
    wire spads_empty;
    wire shift;
    
    wire rd_data;
    wire wr_psum, wr_psum_r, wr_psum_rr;
    wire pad, pad_r, pad_rr;
    
    
    wire ifmap_spad_full_w;
    wire filter_spad_full_w;
    
    wire zero_flag;
    
    wire [q_WIDTH + S_WIDTH - 1:0]           ifmap_spad_depth;
    wire [p_WIDTH + q_WIDTH + S_WIDTH - 1:0] filter_spad_depth;
    
    wire en_mul, en_mul_r;
    
    wire forward;
    
    zero_skipping #(
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(IFMAP_SPAD_DEPTH)      
    ) zero_skipping_inst (
        .clk(clk),     
        .reset(reset | reset_ifmap_spad),   
        
        .shift(shift),
                
        .w_en(wr_ifmap),
        .din(ifmap_pixel),
        
        .r_addr(ifmap_addr),
        .zero_flag(zero_flag)
    );
    
    assign ifmap_spad_depth = q * S;      
    
    ifmap_spad #(
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(IFMAP_SPAD_DEPTH)
    ) ifmap_spad_inst (
        .clk(clk),
        .reset(reset | reset_ifmap_spad),
        
        .spad_depth(ifmap_spad_depth[IFMAP_ADDR_WIDTH - 1:0]),        
        .shift(shift),
        
        .w_en(wr_ifmap),
        .din(ifmap_pixel),
        
        .r_addr(ifmap_addr),
        .r_en((~zero_flag) & rd_data),
        .dout(ifmap_from_spad),
        
        .full(ifmap_spad_full_w),
        .empty(ifmap_spad_empty)
    );

    assign filter_spad_depth = p * q * S;

    filter_spad  #(
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(FILTER_SPAD_DEPTH)
    ) filter_spad_inst (
        .clk(clk),
        .reset(reset | reset_filter_spad),
        
        .spad_depth(filter_spad_depth[FILTER_ADDR_WIDTH - 1:0]),
        
        .w_en(wr_filter),
        .din(filter_pixel),
        
        .r_en((~zero_flag) & rd_data),
        .r_addr(filter_addr),
        .dout(filter_from_spad),
        
        .full(filter_spad_full_w),
        .empty(filter_spad_empty)
    );
                
    psum_spad #(
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH(PSUM_SPAD_DEPTH)
    ) psum_spad_inst (
        .clk(clk),
        .w_en(wr_psum_rr),
        .din(sum_result),
        .w_addr(psum_addr_rr),
        .r_addr(psum_addr),
        .dout(pusm_from_spad_w)
    );
    
    assign V = p[1:0] * F[1:0];  

    pe_controller #(
        .S_WIDTH(S_WIDTH),
        .F_WIDTH(F_WIDTH),
        .U_WIDTH(U_WIDTH),
        .n_WIDTH(n_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),
        
        .IFMAP_ADDR_WIDTH(IFMAP_ADDR_WIDTH),
        .FILTER_ADDR_WIDTH(FILTER_ADDR_WIDTH),
        .PSUM_ADDR_WIDTH(PSUM_ADDR_WIDTH)
    ) pe_controller_inst (
        .clk(clk),
        .reset(reset),
        .start(~spads_empty),
        .stall(spads_empty),
        .busy(busy),
        
        .S(S),
        .F(F),
        .U(U),
        .n(n),
        .p(p),
        .q(q), 
        .V(V),
        
        .reset_accumulation(reset_accumulation),
        .accumulate_ipsum(accumulate_ipsum),
        .reset_ifmap_spad(reset_ifmap_spad),
        .reset_filter_spad(reset_filter_spad),
        
        .ifmap_addr(ifmap_addr),
        .filter_addr(filter_addr),
        .psum_addr(psum_addr),
                        
        .shift(shift),
        .rd_data(rd_data),
        .wr_psum(wr_psum),
        .pad(pad),
        
        .ipsum_fifo_empty(ipsum_fifo_empty),
        .opsum_fifo_full(opsum_fifo_full)
    );
    
    flopr #(PSUM_ADDR_WIDTH + 3) reg1 (
        .clk(clk),
        .reset(reset),
        .d({psum_addr, wr_psum, accumulate_ipsum, pad}),
        .q({psum_addr_r, wr_psum_r, accumulate_ipsum_r, pad_r})
    );
    
    flopr #(PSUM_ADDR_WIDTH + 3) reg2 (
        .clk(clk),
        .reset(reset),
        .d({psum_addr_r, wr_psum_r, accumulate_ipsum_r, pad_r}),
        .q({psum_addr_rr, wr_psum_rr, accumulate_ipsum_rr, pad_rr})
    );
    
    assign forward = wr_psum_rr & (psum_addr_r == psum_addr_rr);
    
    mux2x1 #(.DATA_WIDTH(DATA_WIDTH)) mux1 (
        .in0(pusm_from_spad_w),
        .in1(sum_result),
        .sel(forward),
        .out(pusm_from_spad)
    );
            
    mux2x1 #(.DATA_WIDTH(DATA_WIDTH)) mux2 (
        .in0(pusm_from_spad),
        .in1({DATA_WIDTH{1'b0}}),
        .sel(reset_accumulation_r),
        .out(mux1_out)
    );
    
    assign mul_in1 = ifmap_from_spad;  
    assign mul_in2 = filter_from_spad;
    assign en_mul = (~zero_flag) & (rd_data);
    
    multiplier #(.DATA_WIDTH(DATA_WIDTH)) multiplier_inst (
        .clk(clk),
        .reset(reset), 
        .enable(en_mul_r),
        .x(mul_in1),
        .y(mul_in2),
        .product(mul_result)
    );
    
    truncator #(.DATA_WIDTH(DATA_WIDTH)) truncator_inst (
        .sel(5'b0),
        .in(mul_result),
        .out(truncated_result)
    );
    
    flopr #(DATA_WIDTH + 2) reg3 (
        .clk(clk),
        .reset(reset),
        .d({mux1_out, en_mul, reset_accumulation}),
        .q({mux1_out_r, en_mul_r, reset_accumulation_r})
    );
      
    mux2x1 #(.DATA_WIDTH(DATA_WIDTH)) mux3 (
        .in0(truncated_result),
        .in1(ipsum_pixel),
        .sel(accumulate_ipsum_rr),
        .out(mux2_out)
    );
    
    assign adder_in1   = mux2_out;
    assign adder_in2   = mux1_out_r;
    assign opsum_pixel = (pad_rr == 1'b1) ? 'b0 : sum_result;
    
    adder #(.DATA_WIDTH(DATA_WIDTH)) adder_inst (
		.x(adder_in1),
		.y(adder_in2),
		.sum(sum_result)
	);

    assign spads_empty = filter_spad_empty | ifmap_spad_empty;
    assign ifmap_spad_full = ifmap_spad_full_w | shift | reset_ifmap_spad;
    assign filter_spad_full = filter_spad_full_w | reset_filter_spad;
    
    assign pop_ipsum  = accumulate_ipsum_rr | pad_rr;
    assign push_opsum = accumulate_ipsum_rr | pad_rr;
    
endmodule

