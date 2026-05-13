module PE
    #(parameter width = 4,
    parameter SIZE_IFMAP = 4,
    parameter SIZE_FILTER_SRAM = 4,
    parameter ADDR_WIDTH_IFMAP = $clog2(SIZE_IFMAP),
    parameter ADDR_WIDTH_FILTER = $clog2(SIZE_FILTER_SRAM),
    parameter FILTER_WIDTH = $clog2(SIZE_FILTER_SRAM),
    parameter PSUM_SIZE = 32,
    parameter ADDR_WIDTH_PSUM = $clog2(PSUM_SIZE),
    parameter BUFFER_SIZE = 32,         //NEW
    parameter W_PARAM = 1,              //NEW
    parameter R_PARAM = 1)              //NEW
    (input clk,
    input rst,
    input rst_buf,                      //NEW
    input start,
                                        // input ready,
                                        // input valid_ifmap,
                                        // input valid_filter,
    input change_mode,
    input func,
                                        // input end_signal,
                                        // input valid_psum_buf,
    input [1:0] mode,
    input [FILTER_WIDTH-1:0] filter_size,
                                        // input [width-1:0] inp_buf_ifmap,
                                        // input [width-1:0] inp_buf_filter,
    input write_en_ifmap,               //NEW
    input write_en_filter,              //NEW
    input write_en_psum_buf,            //NEW
    input read_en_buf,                  //NEW
    input [width+1:0] ifmap_buffer_inp, //NEW
    input [width-1:0] filter_buffer_inp,//NEW
    input [width-1:0] psum_buffer_inp,  //NEW
    // input from psum buffer
                                        // input [width-1:0] inp_buf_psum,
    input [ADDR_WIDTH_IFMAP-1:0] stride,
                                        // output [width-1:0] out_buf,
                                        // output read_en_filter_buf, 
                                        // output read_en_ifmap_buf,
    // for psum buf
                                        // output read_en_psum_buf,
                                        // output write_en_buf,
    output stall, 
    output done_out,
    output ready_ifmap_buf,              //NEW
    output valid_ifmap,                  //NEW
    output ready_filter_buf,             //NEW
    output ready_psum_buf,               //NEW
    output valid,                        //NEW
    output sum_done,                     //NEW
    output [width-1:0] out);             //NEW

    // wires
    wire read_en_filter_buf, read_en_ifmap_buf, read_en_psum_buf, write_en_buf, ready, valid_filter, valid_psum_buf, start_signal, end_signal;       //NEW
    wire [width-1:0] out_buf, inp_buf_ifmap, inp_buf_filter, inp_buf_psum;         //NEW
    wire [width+1:0] inp_buf_ifmap_temp;         //NEW
    wire double_read, initial_val, double_read_done;
    wire mux_sel;
    wire rst_cnt_write_psum, psum_write_buf_cnt_en;
    wire existing_psum_en;
    wire psum_write_ld, psum_write_co;
    wire psum_ren, psum_wen, psum_cnt_en, psum_co;
    wire [$clog2(PSUM_SIZE) - 1:0] psum_r_addr, psum_w_addr, psum_cnt_out, op_count, existing_psum, ex_psum_co;
    wire op_count_en, op_co;
    wire rst_add_reg, en_final_reg, ifmap_read_en, ifmap_write_en, filter_read_en, filter_write_en;
    wire start_pipe, done, cant_read, en_stride, rst_stride, co_stride ,rst_controller, rst_filter;
    wire read_cnt_filter_en, ld_read_cnt_filter, cout_read_cnt_filter;
    wire co_read_filter_cont, finish_filter, en_base_filter, co_base, co_read_data_cont, finish_inp,write_cnt_en, cout_write_cnt_data;
    wire co_temp, co_excess;
    wire read_cnt_data_en,en_offset, rst_offset, co_offset, ld_read_cnt_data, cout_read_cnt_data;
    wire [(2 * ADDR_WIDTH_IFMAP) - 1 : 0] pout_offset_data_temp;
    wire [ADDR_WIDTH_FILTER - 1 : 0] pout_write_cnt, filter_address_write, existing_in_filter,pout_offset_filter;
    wire [(ADDR_WIDTH_FILTER) - 1 : 0] filter_address_read, filter_address_read_temp;
    wire [(2 * ADDR_WIDTH_FILTER) - 1 : 0] pout_offset_filter_temp;
    wire [ADDR_WIDTH_IFMAP - 1 : 0] ifmap_address_read, ifmap_address_write, existing_in_data, pout_offset_data, pout_stride;
    wire [ADDR_WIDTH_FILTER - 1 : 0] pout_base_filter;

    // assigns
    assign {start_signal, end_signal, inp_buf_ifmap} = inp_buf_ifmap_temp;          //NEW
    assign pout_offset_filter = pout_offset_filter_temp[ADDR_WIDTH_FILTER-1:0];
    assign {co_temp, filter_address_read_temp} = pout_base_filter + pout_offset_filter;
    // assign double read and intial value
    assign double_read = (mode == 2'd1);
    assign initial_val = op_count > 0;
    // assign final filter read address
    assign filter_address_read = (double_read && initial_val) ? 2 * filter_address_read_temp + 1'b1
                                : (double_read) ? 2 * filter_address_read_temp
                                : filter_address_read_temp;
    assign pout_offset_data = pout_offset_data_temp[ADDR_WIDTH_IFMAP-1:0];
    assign cant_read = ((filter_address_read >= existing_in_filter) && (~finish_filter)) || ((ifmap_address_read >= existing_in_data) && (~finish_inp));
    assign {co_excess, ifmap_address_read} = pout_stride + pout_offset_data;
    assign done_out = done;
    // psum scratchpad write address
    assign psum_w_addr = (double_read && initial_val) ? 2 * psum_cnt_out + 1'b1
                        : (double_read) ? 2 * psum_cnt_out
                        : psum_cnt_out;

    // datapath
    datapath #(.WIDTH(width),.SIZE_IFMAP(SIZE_IFMAP),.SIZE_SRAM(SIZE_FILTER_SRAM), .ADDR_WIDTH_IFMAP(ADDR_WIDTH_IFMAP),.ADDR_WIDTH_FILTER(ADDR_WIDTH_FILTER), .PSUM_SIZE(PSUM_SIZE))
            dp(.clk(clk), .rst(rst), .reset_reg(rst_add_reg), .reg_en(en_final_reg), .ifmap_ren(ifmap_read_en), .ifmap_wen(ifmap_write_en), .ifmap_r_addr(ifmap_address_read),
               .ifmap_w_addr(existing_in_data), .ifmap_din(inp_buf_ifmap), .filter_ren(filter_read_en), .filter_wen(filter_write_en), .filter_r_addr(filter_address_read),
               .filter_w_addr(existing_in_filter), .filter_din(inp_buf_filter), .psum_ren(psum_ren), .psum_wen(psum_wen), .inp_buf(inp_buf_psum), .psum_r_addr(psum_r_addr), .psum_w_addr(psum_w_addr), .mux_sel(mux_sel), .add_out(out_buf));

    // counters
    // counter for read from filter
    filter_read_cnt #(.SRAM_SIZE(SIZE_FILTER_SRAM),.F_SIZE(ADDR_WIDTH_FILTER)) c1 (.clk(clk),.rst(rst | rst_filter), .en(read_cnt_filter_en),.filter_size(filter_size),.co(cout_read_cnt_filter), .dout(existing_in_filter));
    // write counter
    write_cnt #(.WIDTH(ADDR_WIDTH_FILTER),.SIZE(SIZE_FILTER_SRAM)) c2(.clk(clk), .rst(rst | rst_controller),.en(write_cnt_en), .double_read(double_read), .filter_size(filter_size), .filter_done(finish_filter), .dout(pout_write_cnt), .co(cout_write_cnt_data));
    // counter for stride movement
    stride_cnt #(.IFMAP_DATA_WIDTH(ADDR_WIDTH_IFMAP), .FILTER_DATA_WIDTH(ADDR_WIDTH_FILTER)) c3(.clk(clk), .rst(rst | rst_controller), .reset_stride(rst_stride), .en(en_stride), .input_done(finish_inp), .filter_size(filter_size), .stride(stride), .input_out(existing_in_data), .dout(pout_stride), .co(co_stride));
    // counter for filter indexing
    filter_num_cnt #(.WIDTH(ADDR_WIDTH_FILTER)) c4(.clk(clk),.rst(rst | rst_controller), .en(en_base_filter), .val(filter_size), .dout(pout_base_filter), .co(co_base));
    filter_inner_cnt #(.WIDTH(ADDR_WIDTH_FILTER)) c5(.clk(clk), .rst(rst | rst_controller), .en(en_offset), .reset_in(rst_offset), .filter_size(filter_size), .dout(pout_offset_filter_temp), .co(co_offset));
    // data indexing
    filter_inner_cnt #(.WIDTH(ADDR_WIDTH_IFMAP)) c6(.clk(clk), .rst(rst | rst_controller), .en(en_offset), .reset_in(rst_offset), .filter_size(filter_size), .dout(pout_offset_data_temp), .co());
    // counter for reading the data
    data_read_cnt #(.WIDTH(ADDR_WIDTH_IFMAP)) c7(.clk(clk),.rst(rst | (rst_controller && (~double_read | (op_count > 0)))), .en(read_cnt_data_en), .dout(existing_in_data), .co(cout_read_cnt_data));
    // counter for psum  write address
    counter #(.WIDTH(ADDR_WIDTH_PSUM)) c8(.clk(clk), .rst(rst | (rst_controller && double_read)), .en(psum_cnt_en), .cnt_out(psum_cnt_out), .co(psum_co));
    // counter for counting the number of operations
    counter #(.WIDTH(ADDR_WIDTH_PSUM)) c9(.clk(clk), .rst(rst), .en(op_count_en), .cnt_out(op_count), .co(op_co));
    // counter for counting the number of existing psums
    counter #(.WIDTH(ADDR_WIDTH_PSUM)) c10(.clk(clk), .rst(rst), .en(existing_psum_en), .cnt_out(existing_psum), .co(ex_psum_co));
    // counter for addressing the psum spad and input buffer of psum
    counter_ld #(.WIDTH(ADDR_WIDTH_PSUM)) c11(.clk(clk), .rst(rst | rst_cnt_write_psum), .en(psum_write_buf_cnt_en), .ld(psum_write_ld), .din(existing_psum), .cnt_out(psum_r_addr), .co(psum_write_co)); 

    // controllers
    // controller to read from data buffer
    data_read_controller cont1(.clk(clk), .rst(rst | (rst_controller && (~double_read | (op_count > 0)))), .start_read(start_pipe), .data_read(end_signal), .valid(valid_ifmap), .done(done), .wen(ifmap_write_en), .ren(read_cnt_data_en), .read_buf(read_en_ifmap_buf), .finish_read(finish_inp));
    // controller to read from filter buffer
    filter_read_controller cont2(.clk(clk), .rst(rst | rst_filter), .start_read(start_pipe), .co(cout_read_cnt_filter), .finish_read(finish_filter), .read_buf(read_en_filter_buf), .valid(valid_filter), .done(done), .ren(read_cnt_filter_en), .wen(filter_write_en));
    // main controller
    main_controller #(.OP_WIDTH(ADDR_WIDTH_PSUM)) cont_main(.clk(clk), .rst(rst), .start(start), .stop_read(cant_read), .data_ready(ready), .inner_carry(co_offset), .start_pipe(start_pipe), .write_carry(cout_write_cnt_data), .reset_cont(rst_controller), .stride_carry(co_stride),
                      .reset_reg(rst_add_reg), .stride_en(en_stride), .data_read(ifmap_read_en), .change_mode(change_mode), .func(func), .op_cnt(op_count), .mode(mode), .filter_read(filter_read_en), .inner_en(en_offset), .reg_en(en_final_reg), .reset_filter(rst_filter), .reset_stride(rst_stride), .reset_inner(rst_offset), 
                      .w_buf(write_en_buf), .w_psum(psum_wen), .w_en(write_cnt_en), .ex_psum_en(existing_psum_en), .op_cnt_en(op_count_en), .filter_num_en(en_base_filter), .stall(stall), .mux_sel(mux_sel), .done(done), .psum_cnt_en(psum_cnt_en),
                      .rst_cnt_write_psum(rst_cnt_write_psum), .psum_write_buf_cnt_en(psum_write_buf_cnt_en), .psum_write_ld(psum_write_ld), .psum_write_co(psum_write_co), .psum_input_buf_valid(valid_psum_buf), .psum_inp_buf_ren(read_en_psum_buf), .psum_spad_ren(psum_ren), .sum_done(sum_done));

    //NEW
    // buffers
    // buffer for data
    circular_buffer #(.DATA_WIDTH(width + 2), .BUFFER_SIZE(BUFFER_SIZE), .W_PARAM(W_PARAM), .R_PARAM(R_PARAM)) 
             cb_ifmap(.clk(clk), .rst(rst), .rst_buf(1'b0), .write_en(write_en_ifmap), .read_en(read_en_ifmap_buf), .inp(ifmap_buffer_inp), .full(), .empty(), .ready(ready_ifmap_buf), .valid(valid_ifmap), .data_out(inp_buf_ifmap_temp));
    // buffer for filter
    circular_buffer #(.DATA_WIDTH(width), .BUFFER_SIZE(BUFFER_SIZE), .W_PARAM(W_PARAM), .R_PARAM(R_PARAM)) 
            cb_filter(.clk(clk), .rst(rst), .rst_buf(1'b0), .write_en(write_en_filter), .read_en(read_en_filter_buf), .inp(filter_buffer_inp), .full(), .empty(), .ready(ready_filter_buf), .valid(valid_filter), .data_out(inp_buf_filter));
    // buffer for psum input
    circular_buffer #(.DATA_WIDTH(width), .BUFFER_SIZE(BUFFER_SIZE), .W_PARAM(W_PARAM), .R_PARAM(R_PARAM)) 
              cb_psum(.clk(clk), .rst(rst), .rst_buf(rst_buf), .write_en(write_en_psum_buf), .read_en(read_en_psum_buf), .inp(psum_buffer_inp), .full(), .empty(), .ready(ready_psum_buf), .valid(valid_psum_buf), .data_out(inp_buf_psum));
    // buffer for psum output
    circular_buffer #(.DATA_WIDTH(width), .BUFFER_SIZE(BUFFER_SIZE), .W_PARAM(W_PARAM), .R_PARAM(R_PARAM)) 
               cb_out(.clk(clk), .rst(rst), .rst_buf(1'b0), .write_en(write_en_buf), .read_en(read_en_buf), .inp(out_buf), .full(), .empty(), .ready(ready), .valid(valid), .data_out(out));

endmodule