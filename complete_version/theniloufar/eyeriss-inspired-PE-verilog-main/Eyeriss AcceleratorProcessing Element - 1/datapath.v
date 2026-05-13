module datapath 
    # (parameter WIDTH = 4,
    parameter ADDR_WIDTH_IFMAP = $clog2(SIZE_IFMAP),
    parameter SIZE_IFMAP = 4,
    parameter ADDR_WIDTH_FILTER = $clog2(SIZE_SRAM),
    parameter SIZE_SRAM = 4)
    (input clk, 
    input rst,
    input reset_reg,
    input reg_en,
    input ifmap_ren,
    input ifmap_wen, 
    input filter_ren,
    input filter_wen,
    input [WIDTH-1:0] ifmap_din, 
    input [ADDR_WIDTH_IFMAP-1:0] ifmap_r_addr, 
    input [ADDR_WIDTH_IFMAP-1:0] ifmap_w_addr,
    input [ADDR_WIDTH_FILTER-1:0] filter_r_addr,
    input [ADDR_WIDTH_FILTER-1:0] filter_w_addr,
    input [WIDTH-1:0] filter_din,
    output [WIDTH-1:0] psum_out);

    // wires
    wire adder_cout;
    wire [WIDTH-1:0] ifmap_parout, filter_parout, mult_parout, adder_result, reg_out, mid_reg_out;

    // scratch pads
    RF #(.WIDTH(WIDTH),.SIZE(SIZE_IFMAP),.ADDR_WIDTH(ADDR_WIDTH_IFMAP)) scratchPad_data (.clk(clk), .ren(ifmap_ren), .wen(ifmap_wen), .r_addr(ifmap_r_addr), 
    .w_addr(ifmap_w_addr), .din(ifmap_din),.dout(ifmap_parout));
    SRAM #(.WIDTH(WIDTH),.SIZE(SIZE_SRAM), .ADDR_WIDTH(ADDR_WIDTH_FILTER)) scratchpad_filter (.clk(clk), .ren(filter_ren), .wen(filter_wen), .chip_en(1'b1), 
    .r_addr(filter_r_addr), .w_addr(filter_w_addr), .din(filter_din), .dout(filter_parout));

    // pipeline modules
    multiplier #(.N(WIDTH)) pipe_mult (.a(filter_parout), .b(ifmap_parout), .out(mult_parout));
    adder #(.N(WIDTH)) add (.a(mult_parout), .b(reg_out), .out(adder_result), .co(adder_cout));
    register #(.N(WIDTH)) save_status_register (.clk(clk), .rst(rst | reset_reg),.en(reg_en),.din(mult_parout),.dout(mid_reg_out));
    
    // final reg
    register #(.N(WIDTH)) result_register(.clk(clk), .rst(rst | reset_reg),.en(reg_en),.din(adder_result),.dout(reg_out));

    // assign output
    assign psum_out = reg_out;
endmodule