package shared_pkg;
    
    int error_count;
    int pass_count;
        
    typedef enum bit [1:0] {
        IFMAP  = 2'b00, 
        FILTER = 2'b01, 
        BIAS   = 2'b10,
        PSUM   = 2'b11
    } data_t;
    
    typedef enum bit {
        CONV = 1'b0, 
        MAX  = 1'b1
    } layer_t;
    
    // CONV1 Mapping Parameters    
    localparam CONV1_H = 227;
    localparam CONV1_W = 227;
    localparam CONV1_D = 35;
    localparam CONV1_R = 11;
    localparam CONV1_S = 11;
    localparam CONV1_E = 55;
    localparam CONV1_F = 55;

    localparam CONV1_C = 3;
    localparam CONV1_M = 64;
    localparam CONV1_N = 4;
    localparam CONV1_U = 4;
    
    localparam CONV1_m = 64;
    localparam CONV1_n = 1;
    localparam CONV1_e = 7;
    localparam CONV1_p = 16;
    localparam CONV1_q = 1;
    localparam CONV1_r = 1;
    localparam CONV1_t = 2;
    
    // CONV2 Mapping Parameters    
    localparam CONV2_H = 31;
    localparam CONV2_W = 31;
    localparam CONV2_R = 5;
    localparam CONV2_S = 5;
    localparam CONV2_E = 27;
    localparam CONV2_F = 27;

    localparam CONV2_C = 64;
    localparam CONV2_M = 192;
    localparam CONV2_N = 4;
    localparam CONV2_U = 1;
    
    localparam CONV2_m = 64;
    localparam CONV2_n = 1;
    localparam CONV2_e = 27;
    localparam CONV2_p = 16;
    localparam CONV2_q = 2;
    localparam CONV2_r = 1;
    localparam CONV2_t = 1;
    
    // CONV3 Mapping Parameters    
    localparam CONV3_H = 15;
    localparam CONV3_W = 15;
    localparam CONV3_R = 3;
    localparam CONV3_S = 3;
    localparam CONV3_E = 13;
    localparam CONV3_F = 13;

    localparam CONV3_C = 192;
    localparam CONV3_M = 384;
    localparam CONV3_N = 4;
    localparam CONV3_U = 1;
    
    localparam CONV3_m = 64;
    localparam CONV3_n = 4;
    localparam CONV3_e = 13;
    localparam CONV3_p = 16;
    localparam CONV3_q = 4;
    localparam CONV3_r = 1;
    localparam CONV3_t = 4;
    
    // CONV4 Mapping Parameters
    localparam CONV4_H = 15;
    localparam CONV4_W = 15;
    localparam CONV4_R = 3;
    localparam CONV4_S = 3;
    localparam CONV4_E = 13;
    localparam CONV4_F = 13;

    localparam CONV4_C = 384;
    localparam CONV4_M = 256;
    localparam CONV4_N = 4;
    localparam CONV4_U = 1;
    
    localparam CONV4_m = 64;
    localparam CONV4_n = 4;
    localparam CONV4_e = 13;
    localparam CONV4_p = 16;
    localparam CONV4_q = 3;
    localparam CONV4_r = 2;
    localparam CONV4_t = 2;
    
    // CONV5 Mapping Parameters    
    localparam CONV5_H = 15;
    localparam CONV5_W = 15;
    localparam CONV5_R = 3;
    localparam CONV5_S = 3;
    localparam CONV5_E = 13;
    localparam CONV5_F = 13;

    localparam CONV5_C = 256;
    localparam CONV5_M = 256;
    localparam CONV5_N = 4;
    localparam CONV5_U = 1;
    
    localparam CONV5_m = 64;
    localparam CONV5_n = 4;
    localparam CONV5_e = 13;
    localparam CONV5_p = 16;
    localparam CONV5_q = 3;
    localparam CONV5_r = 2;
    localparam CONV5_t = 2;
               
    // Integer Parameters
    parameter CORE_CLK_PERIOD = 5;            
    parameter LINK_CLK_PERIOD = 11.1111111;       
    
    parameter DATA_WIDTH_IFMAP     = 16; 
    parameter ROW_TAG_WIDTH_IFMAP  = 4;
    parameter COL_TAG_WIDTH_IFMAP  = 5;
    
    parameter DATA_WIDTH_FILTER    = 64; 
    parameter ROW_TAG_WIDTH_FILTER = 4;
    parameter COL_TAG_WIDTH_FILTER = 4;
    
    parameter DATA_WIDTH_PSUM      = 64; 
    parameter ROW_TAG_WIDTH_PSUM   = 4;
    parameter COL_TAG_WIDTH_PSUM   = 4;
    
    parameter NUM_OF_ROWS = 12;
    parameter NUM_OF_COLS = 14;

    parameter GIN_FIFO_DEPTH = 16;
    parameter GON_FIFO_DEPTH = 16;

    parameter IFMAP_FIFO_DEPTH  = 16;
    parameter FILTER_FIFO_DEPTH = 16;
    parameter PSUM_FIFO_DEPTH   = 32;
    
    parameter IFMAP_SPAD_DEPTH  = 12;
    parameter FILTER_SPAD_DEPTH = 224;
    parameter PSUM_SPAD_DEPTH   = 24;

    parameter H_WIDTH = 8;
    parameter W_WIDTH = 8;
    parameter R_WIDTH = 4;
    parameter S_WIDTH = 4;
    parameter E_WIDTH = 6;
    parameter F_WIDTH = 6;
    parameter C_WIDTH = 10;
    parameter M_WIDTH = 10;
    parameter N_WIDTH = 3;
    parameter U_WIDTH = 3;

    parameter m_WIDTH = 8;
    parameter n_WIDTH = 3;
    parameter e_WIDTH = 6;
    parameter p_WIDTH = 5;
    parameter q_WIDTH = 3;
    parameter r_WIDTH = 2;
    parameter t_WIDTH = 3; 

    parameter ROW_MAJOR  = 1;
    parameter ADDR_WIDTH = 20;
    parameter DATA_WIDTH = 16;

    // parameters for Interface unit 
    parameter FIFO_WIDTH = 64;
    parameter FIFO_DEPTH = 16;

    //parameters for GLB's 
    parameter IFMAP_GLB_DEPTH  = 7945;
    parameter FILTER_GLB_DEPTH = 3872;
    parameter PSUM_GLB_DEPTH   = 46656;
    parameter BIAS_GLB_DEPTH   = 64;

    // Logic Signals
    logic core_clk;
    logic link_clk;
    logic reset;

    logic scan_en;
    logic scan_in;
    logic scan_out;

    logic start;
    logic busy;    
    logic done;
       
    logic start_pass;     
    logic pass_done;   
    logic ofmap_dump;  
    logic dump_done;
    
    logic [ADDR_WIDTH-1:0] words_num;
    logic                  transfer_done;
    
    logic                  start_forward;
    logic [1:0]            transfer_type;
    logic                  re_from_dram;
    logic [FIFO_WIDTH-1:0] rdata_from_dram;
    logic                  valid_from_dram;

    logic                  start_backward;
    logic                  we_to_dram;
    logic [FIFO_WIDTH-1:0] wdata_to_dram;
    
    logic [M_WIDTH - 1:0] filter_ids         [0:1]; 
    logic [C_WIDTH - 1:0] filter_channel_ids [0:1];
        
    logic [N_WIDTH - 1:0] ifmap_ids         [0:1]; 
    logic [C_WIDTH - 1:0] ifmap_channel_ids [0:1]; 
        
    logic [N_WIDTH - 1:0] psum_ids         [0:1]; 
    logic [M_WIDTH - 1:0] psum_channel_ids [0:1];
        
    task initialize_dut();
        begin
            // Clock & reset
            core_clk = 0;
            link_clk = 0;
            reset    = 0;

            // Scan chain signals
            scan_en = 0;
            scan_in = 0;

            // Control signals
            start = 0;
            start_pass = 0;
            dump_done = 0;
            
            // FIFO interface signals
            words_num       = 0;
            start_forward   = 0;
            start_backward  = 0;
            transfer_type   = 0;
            rdata_from_dram = 0;
            valid_from_dram = 0;
        end
    endtask

    task wait_core_cycle(
        input int num_cycle
    );
        repeat(num_cycle) @(posedge core_clk);
    endtask
    
    task wait_link_cycle(
        input int num_cycle
    );
        repeat(num_cycle) @(posedge link_clk);
    endtask
    
    task assert_reset();
        begin
            shared_pkg::reset = 1;
            wait_core_cycle(1);
            shared_pkg::reset = 0;
        end
    endtask
        
endpackage : shared_pkg
