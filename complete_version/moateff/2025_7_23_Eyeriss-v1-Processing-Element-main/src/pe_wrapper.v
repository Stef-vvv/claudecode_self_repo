module pe_wrapper
#(   
    parameter DATA_WIDTH_IFMAP  = 16,
    parameter DATA_WIDTH_FILTER = 64,
    parameter DATA_WIDTH_PSUM   = 64,
    
    parameter IFMAP_FIFO_DEPTH  = 8,
    parameter FILTER_FIFO_DEPTH = 8,
    parameter PSUM_FIFO_DEPTH   = 8,
    
    parameter DATA_WIDTH = 16,
        
    parameter W_WIDTH = 8,
    parameter S_WIDTH = 5,
    parameter F_WIDTH = 6,
    parameter U_WIDTH = 3,
    parameter n_WIDTH = 3,
    parameter p_WIDTH = 5,
    parameter q_WIDTH = 3,
    
    parameter IFMAP_SPAD_DEPTH  = 12,
    parameter FILTER_SPAD_DEPTH = 224,
    parameter PSUM_SPAD_DEPTH   = 24
) (
    // Clock and Reset
    input clk,   
    input reset,         
    
    // Control Signals
    input  enable,
    input  configure,
    output busy,
    
    // Configurations
    input [W_WIDTH - 1:0] W,    
    input [S_WIDTH - 1:0] S,    
    input [F_WIDTH - 1:0] F,
    input [U_WIDTH - 1:0] U,
    input [n_WIDTH - 1:0] n,    
    input [p_WIDTH - 1:0] p,      
    input [q_WIDTH - 1:0] q,                       

    // Interface with FIFOs
    input  [DATA_WIDTH_IFMAP - 1:0] ifmap,        
    input                           push_ifmap, 
    output                          ifmap_fifo_full,
    
    input  [DATA_WIDTH_FILTER - 1:0] filter,          
    input                            push_filter,      
    output                           filter_fifo_full,

    input  [DATA_WIDTH_PSUM - 1:0] ipsum,       
    input                          push_ipsum,   
    output                         ipsum_fifo_full,
    
    // Output Data Interface
    output [DATA_WIDTH_PSUM - 1:0] opsum,  
    input                          pop_opsum,    
    output                         opsum_fifo_empty
);

    wire gated_clk;
    
    clk_gating clk_gating_inst (
        .enable(enable),
        .clk(clk),
        .gated_clk(gated_clk)
    );
       
    wire [DATA_WIDTH - 1:0] ifmap_from_fifo;
    wire                    pop_ifmap;
    wire                    ifmap_fifo_empty;
                 
    wire [DATA_WIDTH - 1:0] filter_from_fifo;
    wire                    pop_filter;
    wire                    filter_fifo_empty;
    
    wire [DATA_WIDTH - 1:0] ipsum_from_fifo;
    wire                    pop_ipsum;
    wire                    ipsum_fifo_empty;
    
    wire [DATA_WIDTH - 1:0] opsum_to_fifo;
    wire                    push_opsum;
    wire                    opsum_fifo_full;
    
    wire filter_spad_full;
    wire ifmap_spad_full;
        
    assign pop_filter = (~filter_spad_full) & (~filter_fifo_empty);
    assign pop_ifmap  = (~ifmap_spad_full) & (~ifmap_fifo_empty);
    
    fifo_top #(
        .R_DATA_WIDTH(DATA_WIDTH),
        .W_DATA_WIDTH(DATA_WIDTH_IFMAP),
        .FIFO_DEPTH(IFMAP_FIFO_DEPTH)
    ) ifmap_fifo_inst (
        .clk(gated_clk),
        .reset(reset),
        .write_request(push_ifmap),
        .read_request(pop_ifmap),
        .wr_data(ifmap),
        .rd_data(ifmap_from_fifo),
        // .almost_full_flag(),
        // .almost_empty_flag(),
        .full_flag(ifmap_fifo_full),
        .empty_flag(ifmap_fifo_empty)
    );
    
    fifo_wrapper #(
        .R_DATA_WIDTH(DATA_WIDTH),
        .W_DATA_WIDTH(DATA_WIDTH_FILTER),
        .FIFO_DEPTH(FILTER_FIFO_DEPTH)
    ) filter_fifo_inst (
        .clk(gated_clk),
        .reset(reset),
        .write_request(push_filter),
        .read_request(pop_filter),
        .wr_data(filter),
        .rd_data(filter_from_fifo),
        // .almost_full_flag(),
        // .almost_empty_flag(),
        .full_flag(filter_fifo_full),
        .empty_flag(filter_fifo_empty)
    );
        
    fifo_top #(
        .R_DATA_WIDTH(DATA_WIDTH),
        .W_DATA_WIDTH(DATA_WIDTH_PSUM),
        .FIFO_DEPTH(PSUM_FIFO_DEPTH)
    ) ipsum_fifo_inst (
        .clk(gated_clk),
        .reset(reset),
        .write_request(push_ipsum),
        .read_request(pop_ipsum),
        .wr_data(ipsum),
        .rd_data(ipsum_from_fifo),
        // .almost_full_flag(),
        .almost_empty_flag(ipsum_fifo_empty),
        .full_flag(ipsum_fifo_full)
        // .empty_flag()
    );
    
    fifo_top #(
        .R_DATA_WIDTH(DATA_WIDTH_PSUM),
        .W_DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(PSUM_FIFO_DEPTH)
    ) opsum_fifo_inst (
        .clk(gated_clk),
        .reset(reset),
        .write_request(push_opsum),
        .read_request(pop_opsum),
        .wr_data(opsum_to_fifo),
        .rd_data(opsum),
        .almost_full_flag(opsum_fifo_full),
        // .almost_empty_flag(),
        // .full_flag(),
        .empty_flag(opsum_fifo_empty)
    );
    
    pe #(
        .DATA_WIDTH(DATA_WIDTH),
        
        .W_WIDTH(W_WIDTH),
        .S_WIDTH(S_WIDTH),
        .F_WIDTH(F_WIDTH),
        .U_WIDTH(U_WIDTH),
        .n_WIDTH(n_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),
        
        .IFMAP_SPAD_DEPTH(IFMAP_SPAD_DEPTH),
        .FILTER_SPAD_DEPTH(FILTER_SPAD_DEPTH),
        .PSUM_SPAD_DEPTH(PSUM_SPAD_DEPTH)
    ) pe_inst (
        .clk(gated_clk),
        .reset(reset),
        .busy(busy),
        .configure(configure),
        
        .W(W),
        .S(S),
        .F(F),
        .U(U),
        .n(n),
        .p(p),
        .q(q),    
                              
        .wr_filter(pop_filter),
        .filter_pixel(filter_from_fifo),
        .filter_spad_full(filter_spad_full),

        .wr_ifmap(pop_ifmap),
        .ifmap_pixel(ifmap_from_fifo),
        .ifmap_spad_full(ifmap_spad_full),
        
        .pop_ipsum(pop_ipsum),
        .ipsum_pixel(ipsum_from_fifo),
        .ipsum_fifo_empty(ipsum_fifo_empty),
       
        .push_opsum(push_opsum),
        .opsum_pixel(opsum_to_fifo),
        .opsum_fifo_full(opsum_fifo_full)
    );
        
endmodule