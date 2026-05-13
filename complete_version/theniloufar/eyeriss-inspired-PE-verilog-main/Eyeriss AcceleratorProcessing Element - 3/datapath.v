module datapath 
    # (parameter WIDTH = 4,
    parameter SIZE_IFMAP = 4,
    parameter ADDR_WIDTH_IFMAP = $clog2(SIZE_IFMAP),
    parameter SIZE_SRAM = 4,
    parameter ADDR_WIDTH_FILTER = $clog2(SIZE_SRAM),
    parameter PSUM_SIZE = 32,
    parameter ADDR_WIDTH_PSUM = $clog2(PSUM_SIZE))
    (input clk, 
    input rst,
    input reset_reg,
    input reg_en,
    input ifmap_ren,
    input ifmap_wen, 
    input filter_ren,
    input filter_wen,
    input mux_sel,
    // inputs for psum spad
    input psum_ren,
    input psum_wen,
    input [WIDTH-1:0] inp_buf,
    input [WIDTH-1:0] ifmap_din, 
    input [ADDR_WIDTH_IFMAP-1:0] ifmap_r_addr, 
    input [ADDR_WIDTH_IFMAP-1:0] ifmap_w_addr,
    input [ADDR_WIDTH_FILTER-1:0] filter_r_addr,
    input [ADDR_WIDTH_FILTER-1:0] filter_w_addr,
    input [ADDR_WIDTH_PSUM-1:0] psum_r_addr,
    input [ADDR_WIDTH_PSUM-1:0] psum_w_addr,
    input [WIDTH-1:0] filter_din,
    output [WIDTH-1:0] add_out);

    // wires
    wire adder_cout;
    wire [WIDTH-1:0] ifmap_parout, filter_parout, mult_parout, adder_result, reg_out, mid_reg_out, op1, op2, psum_out;

    // scratch pads
    RF #(.WIDTH(WIDTH),.SIZE(SIZE_IFMAP),.ADDR_WIDTH(ADDR_WIDTH_IFMAP)) scratchPad_data (.clk(clk), .ren(ifmap_ren), .wen(ifmap_wen), .r_addr(ifmap_r_addr), 
         .w_addr(ifmap_w_addr), .din(ifmap_din),.dout(ifmap_parout));
    SRAM #(.WIDTH(WIDTH),.SIZE(SIZE_SRAM), .ADDR_WIDTH(ADDR_WIDTH_FILTER)) scratchpad_filter (.clk(clk), .ren(filter_ren), .wen(filter_wen), .chip_en(1'b1), 
           .r_addr(filter_r_addr), .w_addr(filter_w_addr), .din(filter_din), .dout(filter_parout));

    // pipeline modules
    multiplier #(.N(WIDTH)) pipe_mult (.a(filter_parout), .b(ifmap_parout), .out(mult_parout));
    mux2 #(.N(WIDTH)) m1 (.a(mult_parout), .b(inp_buf), .src(mux_sel), .out(op1));
    mux2 #(.N(WIDTH)) m2 (.a(reg_out), .b(psum_out), .src(mux_sel), .out(op2));
    adder #(.N(WIDTH)) add (.a(op1), .b(op2), .out(adder_result), .co(adder_cout));
    
    // reg
    register #(.N(WIDTH)) result_register(.clk(clk), .rst(rst | reset_reg), .en(reg_en), .din(adder_result), .dout(reg_out));

    // psum scratchpad
    RF #(.WIDTH(WIDTH), .SIZE(PSUM_SIZE), .ADDR_WIDTH(ADDR_WIDTH_PSUM)) scratchpad_psum (.clk(clk), .ren(psum_ren), .wen(psum_wen), .r_addr(psum_r_addr),
         .w_addr(psum_w_addr), .din(reg_out), .dout(psum_out));

    // assign output
    assign add_out = adder_result;
endmodule