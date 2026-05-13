module toplevel
    #(parameter DATA_WIDTH = 4,
    parameter SIZE_IFMAP = 4,
    parameter SIZE_FILTER_SRAM = 4,
    parameter PSUM_SIZE = 32,
    parameter BUFFER_SIZE = 32,
    parameter W_PARAM = 1,
    parameter R_PARAM = 1,
    parameter ADDR_WIDTH_FILTER = $clog2(SIZE_FILTER_SRAM),
    parameter ADDR_WIDTH_IFMAP = $clog2(SIZE_IFMAP),
    parameter N = 5,
    parameter N_ADDR = $clog2(N),
    parameter KB = 32,
    parameter SIZE_GLOBAL = (KB * 8192) / DATA_WIDTH,
    parameter ADDR_WIDTH_GLOBAL = $clog2(SIZE_GLOBAL),
    parameter NUM_OF_FILTERS = 3,
    parameter ADDR_NUM_OF_FILTERS = $clog2(NUM_OF_FILTERS))
    (input clk,
    input rst,
    input start,
    input [1:0] mode,
    input [ADDR_WIDTH_IFMAP-1:0] stride,
    input [ADDR_WIDTH_FILTER-1:0] filter_size,
    input [ADDR_WIDTH_GLOBAL-1:0] last_global_index,
    output finish);

    // wires
    wire done, func;
    wire can_start, end_read;
    wire ren_global, wen_global;
    wire read_addr_en, write_addr_en, write_addr_ld, read_addr_clr;
    wire PE_number_en, filter_number_en, PE_number_clr, filter_number_clr, last_PE, last_filter;
    wire [ADDR_WIDTH_GLOBAL-1:0] read_addr, write_addr;
    wire [DATA_WIDTH+1:0] out_global;
    wire [N_ADDR-1:0] PE_index;
    wire [ADDR_NUM_OF_FILTERS-1:0] filter_index;
    // N instances of each signal for each PE
    wire [0:N-1] done_outs, change_modes, rst_bufs, sum_dones, stalls;
    wire [0:N-1] write_en_ifmaps, write_en_filters, write_en_psum_bufs, read_en_bufs;
    wire [0:N-1] ready_ifmap_bufs, ready_filter_bufs, ready_psum_bufs;
    wire [0:N-1] valids, valid_ifmaps;
    wire [DATA_WIDTH-1:0] psum_buffer_inps [0:N-1];
    wire [DATA_WIDTH-1:0] outs [0:N-1];   

    // assigns
    // done if all of PEs done
    assign done = &done_outs;
    // all of PEs can start simultaneous if all of their ifmap buffers are valid
    assign can_start = &valid_ifmaps;

    // datapath
    // an instance of the global buffer
    SRAM_File #(
        .WIDTH(DATA_WIDTH + 2),
        .SIZE(SIZE_GLOBAL)
    ) global_buffer (
        .clk(clk),
        .ren(ren_global), 
        .wen(wen_global), 
        .chip_en(1'b1), 
        .r_addr(read_addr),
        .w_addr(write_addr), 
        .din({2'b0, outs[N-1]}), 
        .dout(out_global)
    );

    // N instances of PE unit
    PE #(
        .width(DATA_WIDTH),
        .SIZE_IFMAP(SIZE_IFMAP),
        .SIZE_FILTER_SRAM(SIZE_FILTER_SRAM),
        .PSUM_SIZE(PSUM_SIZE),
        .BUFFER_SIZE(BUFFER_SIZE),
        .W_PARAM(W_PARAM),
        .R_PARAM(R_PARAM)
    ) pe [0:N-1] (
        .clk(clk),
        .rst(rst),
        .rst_buf(rst_bufs),
        .start(start),
        .change_mode(change_modes),
        .func(func),
        .mode(mode),
        .filter_size(filter_size),
        .write_en_ifmap(write_en_ifmaps),           
        .write_en_filter(write_en_filters),        
        .write_en_psum_buf(write_en_psum_bufs), 
        .read_en_buf(read_en_bufs),    
        .ifmap_buffer_inp(out_global),
        .filter_buffer_inp(out_global[DATA_WIDTH-1:0]),
        .psum_buffer_inp(psum_buffer_inps),
        .stride(stride),
        .stall(stalls),
        .done_out(done_outs),
        .ready_ifmap_buf(ready_ifmap_bufs),
        .valid_ifmap(valid_ifmaps),              
        .ready_filter_buf(ready_filter_bufs),             
        .ready_psum_buf(ready_psum_bufs),               
        .valid(valids),      
        .sum_done(sum_dones),                  
        .out(outs)
    );

    // counters
    // counter for read address from the global buffer
    counter_co #(.WIDTH(ADDR_WIDTH_GLOBAL)) read_addr_generator (.clk(clk), .rst(rst | read_addr_clr), .en(read_addr_en), .din(last_global_index), .cnt_out(read_addr), .co(end_read));
    // counter for write address to the global buffer
    counter_load #(.WIDTH(ADDR_WIDTH_GLOBAL)) write_addr_generator (.clk(clk), .rst(rst), .en(write_addr_en), .ld(write_addr_ld), .din(SIZE_GLOBAL/2), .cnt_out(write_addr), .co());
    // counter for counting number of PEs 
    counter_co #(.WIDTH(N_ADDR)) PE_number (.clk(clk), .rst(rst | PE_number_clr), .en(PE_number_en), .din(N-1), .cnt_out(PE_index), .co(last_PE));
    // counter for counting number of filters for each PE
    counter_co #(.WIDTH(ADDR_NUM_OF_FILTERS)) filter_number (.clk(clk), .rst(rst | filter_number_clr), .en(filter_number_en), .din(NUM_OF_FILTERS-1), .cnt_out(filter_index), .co(last_filter));

    // controller
    controller_global #(
        .N(N)
    ) cont_global (
        .clk(clk),
        .rst(rst),
        .start(start),
        .last_PE(last_PE),
        .last_filter(last_filter),
        .done(done),
        .can_start(can_start),
        .end_read(end_read),
        .PE_index(PE_index),
        .sum_dones(sum_dones),
        .ready_ifmap_bufs(ready_ifmap_bufs),
        .ready_filter_bufs(ready_filter_bufs),
        .valids(valids),
        .ren_global(ren_global),
        .wen_global(wen_global),
        .write_addr_ld(write_addr_ld),
        .read_addr_en(read_addr_en),
        .write_addr_en(write_addr_en),
        .PE_number_en(PE_number_en),
        .filter_number_en(filter_number_en),
        .read_addr_clr(read_addr_clr),
        .PE_number_clr(PE_number_clr),
        .filter_number_clr(filter_number_clr),
        .func(func),
        .finish(finish),
        .rst_bufs(rst_bufs),
        .change_modes(change_modes),
        .write_en_ifmaps(write_en_ifmaps),
        .write_en_filters(write_en_filters),
        .write_en_psum_bufs(write_en_psum_bufs),
        .read_en_bufs(read_en_bufs)
    );

    // cascading input and output psum buffers
    genvar i;
    generate
        for (i = 0; i < N-1; i = i + 1) begin : psum_cascade
            assign psum_buffer_inps[i + 1] = outs[i]; 
        end
    endgenerate

endmodule