module toplevel
    #(parameter width = 4,
    parameter SIZE_IFMAP = 4,
    parameter SIZE_FILTER_SRAM = 4,
    parameter ADDR_WIDTH_IFMAP = $clog2(SIZE_IFMAP),
    parameter ADDR_WIDTH_FILTER = $clog2(SIZE_FILTER_SRAM),
    parameter filter_width = $clog2(SIZE_FILTER_SRAM))
    (input clk,
    input rst,
    input start,
    input ready,
    input valid_ifmap,
    input valid_filter,
    input end_signal,
    input [filter_width-1:0] filter_size,
    input [width-1:0] inp_buf_ifmap,
    input [width-1:0] inp_buf_filter,
    input [ADDR_WIDTH_IFMAP-1:0] stride,
    output [width-1:0] out_buf,
    output read_en_filter_buf, 
    output read_en_ifmap_buf, 
    output write_en_buf, 
    output stall, 
    output done_out);

    // wires
    wire rst_add_reg, en_final_reg, ifmap_read_en, ifmap_write_en, filter_read_en, filter_write_en;
    wire start_pipe, done, cant_read, en_stride, rst_stride, co_stride ,rst_controller, rst_filter;
    wire read_cnt_filter_en, ld_read_cnt_filter, cout_read_cnt_filter;
    wire co_read_filter_cont, finish_filter, en_base_filter, co_base, co_read_data_cont, finish_inp,write_cnt_en, cout_write_cnt_data;
    wire co_temp, co_excess;
    wire read_cnt_data_en,en_offset, rst_offset, co_offset, ld_read_cnt_data, cout_read_cnt_data;
    wire [(2 * ADDR_WIDTH_IFMAP) - 1 : 0] pout_offset_data_temp;
    wire [ADDR_WIDTH_FILTER - 1 : 0] pout_write_cnt, filter_address_read, filter_address_write, pout_read_cnt_filter,pout_offset_filter;
    wire [(2 * ADDR_WIDTH_FILTER) - 1 : 0] pout_offset_filter_temp;
    wire [ADDR_WIDTH_IFMAP - 1 : 0] ifmap_address_read, ifmap_address_write, pout_read_cnt_data, pout_offset_data, pout_stride;
    wire [ADDR_WIDTH_FILTER - 1 : 0] pout_base_filter;

    // assigns
    assign pout_offset_filter = pout_offset_filter_temp[ADDR_WIDTH_FILTER-1:0];
    assign {co_temp, filter_address_read} = pout_base_filter + pout_offset_filter; 
    assign pout_offset_data = pout_offset_data_temp[ADDR_WIDTH_IFMAP-1:0];
    assign cant_read = ((filter_address_read >= pout_read_cnt_filter) && (~finish_filter)) || ((ifmap_address_read >= pout_read_cnt_data) && (~finish_inp));
    assign {co_excess, ifmap_address_read} = pout_stride + pout_offset_data;
    assign done_out = done;

    // datapath
    datapath #(.WIDTH(width),.SIZE_IFMAP(SIZE_IFMAP),.SIZE_SRAM(SIZE_FILTER_SRAM), .ADDR_WIDTH_IFMAP(ADDR_WIDTH_IFMAP),.ADDR_WIDTH_FILTER(ADDR_WIDTH_FILTER))
    dp (.clk(clk), .rst(rst), .reset_reg(rst_add_reg), .reg_en(en_final_reg), .ifmap_ren(ifmap_read_en), .ifmap_wen(ifmap_write_en), .ifmap_r_addr(ifmap_address_read),
    .ifmap_w_addr(pout_read_cnt_data), .ifmap_din(inp_buf_ifmap), .filter_ren(filter_read_en), .filter_wen(filter_write_en), .filter_r_addr(filter_address_read),
    .filter_w_addr(pout_read_cnt_filter), .filter_din(inp_buf_filter), .psum_out(out_buf));

    // counters
    // counter for read from filter
    filter_read_cnt #(.SRAM_SIZE(SIZE_FILTER_SRAM),.F_SIZE(ADDR_WIDTH_FILTER)) c1 (.clk(clk),.rst(rst | rst_filter), .en(read_cnt_filter_en),.filter_size(filter_size),.co(cout_read_cnt_filter), .dout(pout_read_cnt_filter));
    // write counter
    write_cnt #(.WIDTH(ADDR_WIDTH_FILTER),.SIZE(SIZE_FILTER_SRAM)) c2(.clk(clk), .rst(rst | rst_controller),.en(write_cnt_en), .filter_size(filter_size), .filter_done(finish_filter), .dout(pout_write_cnt), .co(cout_write_cnt_data));
    // counter for stride movement
    stride_cnt #(.IFMAP_DATA_WIDTH(ADDR_WIDTH_IFMAP), .FILTER_DATA_WIDTH(ADDR_WIDTH_FILTER)) c3(.clk(clk), .rst(rst | rst_controller), .reset_stride(rst_stride), .en(en_stride), .input_done(finish_inp), .filter_size(filter_size), .stride(stride), .input_out(pout_read_cnt_data), .dout(pout_stride), .co(co_stride));
    // counter for filter indexing
    filter_num_cnt #(.WIDTH(ADDR_WIDTH_FILTER)) c4(.clk(clk),.rst(rst | rst_controller), .en(en_base_filter), .val(filter_size), .dout(pout_base_filter), .co(co_base));
    filter_inner_cnt #(.WIDTH(ADDR_WIDTH_FILTER)) c5(.clk(clk), .rst(rst | rst_controller), .en(en_offset), .reset_in(rst_offset), .filter_size(filter_size), .dout(pout_offset_filter_temp), .co(co_offset));
    // data indexing
    filter_inner_cnt #(.WIDTH(ADDR_WIDTH_IFMAP)) c6(.clk(clk), .rst(rst | rst_controller), .en(en_offset), .reset_in(rst_offset), .filter_size(filter_size), .dout(pout_offset_data_temp), .co());
    // counter for reading the data
    data_read_cnt #(.WIDTH(ADDR_WIDTH_IFMAP)) c7(.clk(clk),.rst(rst | rst_controller), .en(read_cnt_data_en), .dout(pout_read_cnt_data), .co(cout_read_cnt_data));
    
    // controllers
    // controller to read from data buffer
    data_read_controller cont1(.clk(clk), .rst(rst | rst_controller), .start_read(start_pipe), .data_read(end_signal), .valid(valid_ifmap), .done(done), .wen(ifmap_write_en), .ren(read_cnt_data_en), .read_buf(read_en_ifmap_buf), .finish_read(finish_inp));
    // controller to read from filter buffer
    filter_read_controller cont2(.clk(clk), .rst(rst | rst_filter), .start_read(start_pipe), .co(cout_read_cnt_filter), .finish_read(finish_filter), .read_buf(read_en_filter_buf), .valid(valid_filter), .done(done), .ren(read_cnt_filter_en), .wen(filter_write_en));
    // main controller
    main_controller cont_main(.clk(clk), .rst(rst), .start(start), .stop_read(cant_read), .data_ready(ready), .inner_carry(co_offset), .start_pipe(start_pipe), .write_carry(cout_write_cnt_data), .reset_cont(rst_controller), .stride_carry(co_stride),
    .reset_reg(rst_add_reg), .stride_en(en_stride), .data_read(ifmap_read_en), .filter_read(filter_read_en), .inner_en(en_offset), .reg_en(en_final_reg), .reset_filter(rst_filter), .reset_stride(rst_stride), .reset_inner(rst_offset), 
    .w_buf(write_en_buf), .w_en(write_cnt_en), .filter_num_en(en_base_filter), .stall(stall), .done(done));

endmodule