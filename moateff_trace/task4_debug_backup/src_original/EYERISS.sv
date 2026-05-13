/* 
Hint:
-----
This is the top module for the system for now 
we need to integrate the eyeriss module with top_controller

-----------------------------------------------------------------------------------------------
Eyeriss module including these modules:
---------------------------------------
    1) Processing_Units >> Performing (Convolution & Maxpooling)
    2) GLBs_UNIT        >> Sharable Memory between processing unit & FIFO 
    3) INTERFACE_UNIT   >> Interfacing between on-chip memory (GLBs) & off-chip memory (SD card)
    4) SCHEDULER        >> 
    5) SCAN_CHAIN       >> 
    6) ReLU             >> 
------------------------------------------------------------------------------------------------
Expected Inputs:
----------------
 __ clocks, reset, configurations, enables and start signals for scheduling the layers 
    and also the data transfer management.

Expected Outputs:
-----------------
 __ flags (done & busy signals, enables reading from the SD card
            "signals from FIFO interface to DRAM" )

Any other signals >> should be internal signals to all connect the modules with each other
------------------------------------------------------------------------------------------------
Additional Notes:
-----------------
 __ Try to use meaningful naming convention for signals(avoid using letters)
 __ We need to take care of duplicated parameters 
*/

module eyeriss #(
    parameter DATA_WIDTH_IFMAP     = 16, 
    parameter ROW_TAG_WIDTH_IFMAP  = 4,
    parameter COL_TAG_WIDTH_IFMAP  = 5,
    
    parameter DATA_WIDTH_FILTER    = 64, 
    parameter ROW_TAG_WIDTH_FILTER = 4,
    parameter COL_TAG_WIDTH_FILTER = 4,
    
    parameter DATA_WIDTH_PSUM      = 64, 
    parameter ROW_TAG_WIDTH_PSUM   = 4,
    parameter COL_TAG_WIDTH_PSUM   = 4,
    
    parameter NUM_OF_ROWS = 12,
    parameter NUM_OF_COLS = 14,

    parameter GIN_FIFO_DEPTH = 16,
    parameter GON_FIFO_DEPTH = 16,
    
    parameter IFMAP_FIFO_DEPTH  = 16,
    parameter FILTER_FIFO_DEPTH = 16,
    parameter PSUM_FIFO_DEPTH   = 16,
    
    parameter IFMAP_SPAD_DEPTH  = 12,
    parameter FILTER_SPAD_DEPTH = 224,
    parameter PSUM_SPAD_DEPTH   = 24,
    
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
    parameter t_WIDTH = 3,

    parameter ROW_MAJOR  = 1,
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 16,

    // parameters for Interface unit 
    parameter FIFO_WIDTH = 64,
    parameter FIFO_DEPTH = 16,

    //parameters for GLB's 
    parameter IFMAP_GLB_DEPTH  = 7945,
    parameter FILTER_GLB_DEPTH = 3872,
    parameter PSUM_GLB_DEPTH   = 46656,
    parameter BIAS_GLB_DEPTH   = 64
) (
    // General Signals
    input  logic core_clk,
    input  logic link_clk,
    input  logic reset,

    // Scan Chain
    input  logic scan_en, 
    input  logic scan_in,
    output logic scan_out,  

    // Control Signals
    input  logic start,
    output logic busy,    
    output logic done,
       
    input  logic start_pass,     
    output logic pass_done,   
    output logic ofmap_dump,   
    input  logic dump_done,   
    
    // FIFO Interface
    input  logic [ADDR_WIDTH - 1:0] words_num,
    output logic                    transfer_done,
    
    input  logic                    start_forward,
    input  logic [1:0]              transfer_type,
    output logic                    re_from_dram,
    input  logic [FIFO_WIDTH - 1:0] rdata_from_dram,
    input  logic                    valid_from_dram,

    input  logic                    start_backward,
    output logic                    we_to_dram,
    output logic [FIFO_WIDTH - 1:0] wdata_to_dram,
    
    // Scheduler
    output logic [M_WIDTH - 1:0] filter_ids         [0:1], 
    output logic [C_WIDTH - 1:0] filter_channel_ids [0:1],
    
    output logic [N_WIDTH - 1:0] ifmap_ids         [0:1], 
    output logic [C_WIDTH - 1:0] ifmap_channel_ids [0:1], 
    
    output logic [N_WIDTH - 1:0] psum_ids         [0:1], 
    output logic [M_WIDTH - 1:0] psum_channel_ids [0:1]
);

    //--------------------------------------- Signals Declaration---------------------------------------------------\\
    // Signals for  Scan Chain
    // Mapping parameters 
    logic  [H_WIDTH - 1:0] H;
    logic  [W_WIDTH - 1:0] W;
    logic  [R_WIDTH - 1:0] R;
    logic  [S_WIDTH - 1:0] S;
    logic  [E_WIDTH - 1:0] E;
    logic  [F_WIDTH - 1:0] F;
    logic  [C_WIDTH - 1:0] C;
    logic  [M_WIDTH - 1:0] M;
    logic  [N_WIDTH - 1:0] N;
    logic  [U_WIDTH - 1:0] U;
    logic  [m_WIDTH - 1:0] m;
    logic  [n_WIDTH - 1:0] n;
    logic  [e_WIDTH - 1:0] e;
    logic  [p_WIDTH - 1:0] p;
    logic  [q_WIDTH - 1:0] q;
    logic  [r_WIDTH - 1:0] r;
    logic  [t_WIDTH - 1:0] t;
    logic  scan_w;
    
	// Signals for FIFO Interface
    logic                    we_from_fifo_to_ifmap_glb;
	logic [FIFO_WIDTH - 1:0] wdata_from_fifo_to_ifmap_glb;
    logic [ADDR_WIDTH - 1:0] waddr_from_fifo_to_ifmap_glb;

    logic                    we_from_fifo_to_filter_glb;
	logic [FIFO_WIDTH - 1:0] wdata_from_fifo_to_filter_glb;
	logic [ADDR_WIDTH - 1:0] waddr_from_fifo_to_filter_glb;

	logic                    we_from_fifo_to_bias_glb;
	logic [FIFO_WIDTH - 1:0] wdata_from_fifo_to_bias_glb;
	logic [ADDR_WIDTH - 1:0] waddr_from_fifo_to_bias_glb;
        
	logic                    re_from_fifo_to_psum_glb;
	logic [FIFO_WIDTH - 1:0] rdata_from_psum_glb_to_fifo;
	logic [FIFO_WIDTH - 1:0] relued_data_from_psum_glb_to_fifo;
	logic [ADDR_WIDTH - 1:0] raddr_from_fifo_to_psum_glb;      
    
    // Signals for processing unit
    logic                  ifmap_re_from_noc_to_glb;
    logic [ADDR_WIDTH-1:0] ifmap_raddr_from_noc_to_glb;
    logic [DATA_WIDTH-1:0] ifmap_rdata_from_glb_to_noc;

    logic                  filter_re_from_noc_to_glb;
    logic [ADDR_WIDTH-1:0] filter_raddr_from_noc_to_glb;
    logic [DATA_WIDTH-1:0] filter_rdata_from_glb_to_noc;

    logic                  ipsum_re_from_noc_to_glb;
    logic [ADDR_WIDTH-1:0] ipsum_raddr_from_noc_to_glb;
    logic [DATA_WIDTH-1:0] ipsum_rdata_from_glb_to_noc; 
    
    logic [ADDR_WIDTH-1:0] bias_raddr_from_noc_to_glb;
    logic [DATA_WIDTH-1:0] bias_rdata_from_glb_to_noc;

    logic                  opsum_we_from_noc_to_glb;
    logic [ADDR_WIDTH-1:0] opsum_waddr_from_noc_to_glb;
    logic [DATA_WIDTH-1:0] opsum_wdata_from_noc_to_glb;
    
    // Signals for scheduler
    logic bias_sel;
    logic start_noc;
    logic noc_done;
    
    /*--------------------------------------- Shape mapping parameters for config ---------------------------------------------------\\
        the mapping parameters, cnn shape parameters, ids, enables and local network selectors is configured serially bit by 
        bit from the off chip part using scan in , scan enable and clk 
    --------------------------------------------------------------------------------------------------------------------------*/
    scan_chain #(
        .H_WIDTH(H_WIDTH),
        .W_WIDTH(W_WIDTH),
        .R_WIDTH(R_WIDTH),
        .S_WIDTH(S_WIDTH),
        .E_WIDTH(E_WIDTH),
        .F_WIDTH(F_WIDTH),
        .C_WIDTH(C_WIDTH),
        .M_WIDTH(M_WIDTH),
        .N_WIDTH(N_WIDTH),
        .U_WIDTH(U_WIDTH),
        .m_WIDTH(m_WIDTH),
        .n_WIDTH(n_WIDTH),
        .e_WIDTH(e_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),
        .r_WIDTH(r_WIDTH),
        .t_WIDTH(t_WIDTH)
    ) SCAN_CHAIN (
        .clk(core_clk),
        .reset(reset),
        
        .scan_en(scan_en),
        .scan_in(scan_in),
        .scan_out(scan_w),
        
        .H(H),
        .W(W),
        .R(R),
        .S(S),
        .E(E),
        .F(F),
        .C(C),
        .M(M),
        .N(N),
        .U(U),
        .m(m),
        .n(n),
        .e(e),
        .p(p),
        .q(q),
        .r(r),
        .t(t)
    );
 
    /*----------------------------------------- Scheduler Instantiation ---------------------------------------------------\\
        
    ------------------------------------------------------------------------------------------------------------------------*/
    scheduler #(
        .E_WIDTH(E_WIDTH),
        .C_WIDTH(C_WIDTH),
        .M_WIDTH(M_WIDTH),
        .N_WIDTH(N_WIDTH),
        .m_WIDTH(m_WIDTH),
        .n_WIDTH(n_WIDTH),
        .e_WIDTH(e_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),
        .r_WIDTH(r_WIDTH),
        .t_WIDTH(t_WIDTH)
    ) SCHEDULER (
        .clk(core_clk),
        .reset(reset),
        .start(start),
        .busy(busy),
        .done(done),
        
        .start_pass(start_pass),
        .pass_done(pass_done),

        .start_noc(start_noc),
        .noc_done(noc_done),
        
        .ofmap_dump(ofmap_dump),
        .dump_done(dump_done),
        .bias_sel(bias_sel),
                    
        .E(E),
        .C(C),
        .M(M),
        .N(N),
        .m(m),
        .n(n),
        .e(e),
        .p(p),
        .q(q),
        .r(r),
        .t(t),
                
        .filter_ids(filter_ids),
        .filter_channel_ids(filter_channel_ids),
        .ifmap_ids(ifmap_ids),
        .ifmap_channel_ids(ifmap_channel_ids),
        .psum_ids(psum_ids),
        .psum_channel_ids(psum_channel_ids)
    ); 
        
    /*--------------------------------------- Processing Unit Instantiation---------------------------------------------------\\
        The processing unit is the main module of the eyeriss architecture. 
        It performs the convolution and maxpooling operations.
    --------------------------------------------------------------------------------------------------------------------------*/
    processing_unit #(
        .DATA_WIDTH_IFMAP(DATA_WIDTH_IFMAP),
        .ROW_TAG_WIDTH_IFMAP(ROW_TAG_WIDTH_IFMAP),
        .COL_TAG_WIDTH_IFMAP(COL_TAG_WIDTH_IFMAP),

        .DATA_WIDTH_FILTER(DATA_WIDTH_FILTER),
        .ROW_TAG_WIDTH_FILTER(ROW_TAG_WIDTH_FILTER),
        .COL_TAG_WIDTH_FILTER(COL_TAG_WIDTH_FILTER),

        .DATA_WIDTH_PSUM(DATA_WIDTH_PSUM),
        .ROW_TAG_WIDTH_PSUM(ROW_TAG_WIDTH_PSUM),
        .COL_TAG_WIDTH_PSUM(COL_TAG_WIDTH_PSUM),

        .NUM_OF_ROWS(NUM_OF_ROWS),
        .NUM_OF_COLS(NUM_OF_COLS),

        .GIN_FIFO_DEPTH(GIN_FIFO_DEPTH),
        .GON_FIFO_DEPTH(GON_FIFO_DEPTH),

        .IFMAP_FIFO_DEPTH(IFMAP_FIFO_DEPTH),
        .FILTER_FIFO_DEPTH(FILTER_FIFO_DEPTH),
        .PSUM_FIFO_DEPTH(PSUM_FIFO_DEPTH),

        .IFMAP_SPAD_DEPTH(IFMAP_SPAD_DEPTH),
        .FILTER_SPAD_DEPTH(FILTER_SPAD_DEPTH),
        .PSUM_SPAD_DEPTH(PSUM_SPAD_DEPTH),
        
        .H_WIDTH(H_WIDTH),
        .W_WIDTH(W_WIDTH),
        .R_WIDTH(R_WIDTH),
        .S_WIDTH(S_WIDTH),
        .E_WIDTH(E_WIDTH),
        .F_WIDTH(F_WIDTH),
        .U_WIDTH(U_WIDTH),
    
        .m_WIDTH(m_WIDTH),
        .n_WIDTH(n_WIDTH),
        .e_WIDTH(e_WIDTH),
        .p_WIDTH(p_WIDTH),
        .q_WIDTH(q_WIDTH),
        .r_WIDTH(r_WIDTH),
        .t_WIDTH(t_WIDTH),

        .ROW_MAJOR(ROW_MAJOR),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) PROCESSING (
        .clk(core_clk),
        .reset(reset),
        .start(start_noc),
        .done(noc_done),

        .H(H),
        .W(W),
        .R(R),
        .S(S),
        .E(E),
        .F(F),
        .U(U),
        .m(m),
        .n(n),
        .e(e),
        .p(p),
        .q(q),
        .r(r),
        .t(t),

        
        // IFMAP Interface
        .ifmap_re_from_glb(ifmap_re_from_noc_to_glb),
        .ifmap_glb_addr(ifmap_raddr_from_noc_to_glb),
        .ifmap_from_glb(ifmap_rdata_from_glb_to_noc),

        // FILTER Interface
        .filter_re_from_glb(filter_re_from_noc_to_glb),
        .filter_glb_addr(filter_raddr_from_noc_to_glb),
        .filter_from_glb(filter_rdata_from_glb_to_noc),

        // PSUM Interface                
        .ipsum_re_from_glb(ipsum_re_from_noc_to_glb),
        .ipsum_glb_addr(ipsum_raddr_from_noc_to_glb),
        .bias_glb_addr(bias_raddr_from_noc_to_glb),
        .ipsum_from_glb(bias_sel ? bias_rdata_from_glb_to_noc : ipsum_rdata_from_glb_to_noc),
                
        .opsum_we_to_glb(opsum_we_from_noc_to_glb),
        .opsum_glb_addr(opsum_waddr_from_noc_to_glb),
        .opsum_to_glb(opsum_wdata_from_noc_to_glb),

        // Scan Chain
        .scan_en(scan_en),
        .scan_in(scan_w),
        .scan_out(scan_out)
    );

    /*---------------------------------------  INTERFACE_UNIT  Instantiation---------------------------------------------------\\
        It is used to store the data that is being transferred between the processing unit and the GLB.
        Asynch to handle different clock domains (core_clk & link_clk).
    --------------------------------------------------------------------------------------------------------------------------*/
	interface_unit #(
        .FIFO_WIDTH(FIFO_WIDTH),      
        .GLB_WIDTH(DATA_WIDTH),       
        .DEPTH(FIFO_DEPTH),           
        .ADDR_WIDTH(ADDR_WIDTH)      
    ) INTF (
        .core_clk(core_clk),
        .link_clk(link_clk),
        .reset(reset),

        .words_num(words_num),

        .start_forward(start_forward),
        .ifmap_filter_bias_transfer(transfer_type),
        
        .w_en_ifmap_GLB(we_from_fifo_to_ifmap_glb),
        .rdata_to_ifmap_GLB(wdata_from_fifo_to_ifmap_glb),
        .write_address_to_ifmap_GLB(waddr_from_fifo_to_ifmap_glb),    

        .w_en_filter_GLB(we_from_fifo_to_filter_glb),
        .rdata_to_filter_GLB(wdata_from_fifo_to_filter_glb),
        .write_address_to_filter_GLB(waddr_from_fifo_to_filter_glb),

        .w_en_bias_GLB(we_from_fifo_to_bias_glb),
        .rdata_to_bias_GLB(wdata_from_fifo_to_bias_glb),
        .write_address_to_bias_GLB(waddr_from_fifo_to_bias_glb),

        .start_backward(start_backward),
        .wdata_from_GLB(relued_data_from_psum_glb_to_fifo),
        .raddr_from_GLB(raddr_from_fifo_to_psum_glb),

        .r_en_DRAM(re_from_dram),
        .valid_from_DRAM(valid_from_dram),
        .wdata_from_DRAM(rdata_from_dram),
		
        .w_en_DRAM(we_to_dram),
        .r_en_GLB(re_from_fifo_to_psum_glb),
        .rdata_to_DRAM(wdata_to_dram),
        .transfer_done(transfer_done)
    );

    /*--------------------------------------- GLBs Instantiation---------------------------------------------------\\
        The GLB is the shared memory between the processing unit and the FIFO. 
        It is used to store the intermediate results of the processing unit and the data from the FIFO.
        The GLB is a multi-port memory that can be accessed by multiple processing units and FIFOs at the same time.
        The GLB is also used to store the weights and biases of the neural network.
        Consist of 4 buffers:
        ---------------------
        - ifmap buffer  (ifmap pixels)
        - filter buffer (filter weights)
        - psum buffer   (ipsum and opsum)
        - bias buffer   (biases of filters)
    --------------------------------------------------------------------------------------------------------------------------*/    

    glb_unit #(
        .FIFO_WIDTH(FIFO_WIDTH), 
        .DATA_WIDTH(DATA_WIDTH),
        .IFMAP_GLB_DEPTH(IFMAP_GLB_DEPTH),
        .FILTER_GLB_DEPTH(FILTER_GLB_DEPTH),
        .PSUM_GLB_DEPTH(PSUM_GLB_DEPTH),
        .BIAS_GLB_DEPTH(BIAS_GLB_DEPTH)	  
    ) GLB (
        .clk(core_clk),

        //--------------------------------------------IFMAP GLB--------------------------------------------\\
        // port A (64 bits)
        // write port 
        .we_a_ifmap(we_from_fifo_to_ifmap_glb),   
        .addr_a_ifmap(waddr_from_fifo_to_ifmap_glb), 
        .wdata_a_ifmap(wdata_from_fifo_to_ifmap_glb),
        
        // port B (16 bits) 
        // read port
        .re_b_ifmap(ifmap_re_from_noc_to_glb),
        .addr_b_ifmap(ifmap_raddr_from_noc_to_glb),
        .rdata_b_ifmap(ifmap_rdata_from_glb_to_noc),

        //--------------------------------------------FILTER GLB--------------------------------------------\\
        // port A (64 bits)
        // write port 
        .we_a_filter(we_from_fifo_to_filter_glb),   
        .addr_a_filter(waddr_from_fifo_to_filter_glb), 
        .wdata_a_filter(wdata_from_fifo_to_filter_glb),
                
        // port B (16 bits) 
        // read port
        .re_b_filter(filter_re_from_noc_to_glb),
        .addr_b_filter(filter_raddr_from_noc_to_glb),
        .rdata_b_filter(filter_rdata_from_glb_to_noc),
        
        //--------------------------------------------BIAS GLB----------------------------------------------\\
        // port A (64 bits)
        // write port 
        .we_a_bias(we_from_fifo_to_bias_glb),   
        .addr_a_bias(waddr_from_fifo_to_bias_glb), 
        .wdata_a_bias(wdata_from_fifo_to_bias_glb),
                
        // port B (16 bits) 
        // read port
        .re_b_bias(ipsum_re_from_noc_to_glb & bias_sel),
        .addr_b_bias(bias_raddr_from_noc_to_glb),
        .rdata_b_bias(bias_rdata_from_glb_to_noc),
        
        //--------------------------------------------PSUM GLB----------------------------------------------\\
        // port A  
        // write (16 bits) / read (64 bits)                       
        .we_a_psum(opsum_we_from_noc_to_glb),
        .re_a_psum(re_from_fifo_to_psum_glb),
        .addr_a_psum(opsum_we_from_noc_to_glb ? opsum_waddr_from_noc_to_glb : raddr_from_fifo_to_psum_glb),
        .wdata_a_psum(opsum_wdata_from_noc_to_glb),   
        .rdata_a_psum(rdata_from_psum_glb_to_fifo),   
        
        // port B (16 bits)
        // read 
        .re_b_psum(ipsum_re_from_noc_to_glb & (~bias_sel)), 
        .addr_b_psum(ipsum_raddr_from_noc_to_glb),
        .rdata_b_psum(ipsum_rdata_from_glb_to_noc)
    );
    
    /*----------------------------------------- ReLU Instantiation ---------------------------------------------------\\
        
    --------------------------------------------------------------------------------------------------------------------------*/
    relu_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .NUM_INPUTS(FIFO_WIDTH/DATA_WIDTH)
    ) ReLU (
        .in(rdata_from_psum_glb_to_fifo),
        .out(relued_data_from_psum_glb_to_fifo)
    );
        
endmodule
