`timescale 1ns / 1ps

module PE_tb();
    int error_count = 0;
    int pass_count  = 0;

    parameter CLK_PERIOD = 10;
    parameter DATA_WIDTH = 16;
	
    parameter DATA_WIDTH_IFMAP  = 16;
    parameter DATA_WIDTH_FILTER = 64;
    parameter DATA_WIDTH_PSUM   = 64;
    
    parameter IFMAP_FIFO_DEPTH  = 8;
    parameter FILTER_FIFO_DEPTH = 8;
    parameter PSUM_FIFO_DEPTH   = 8;
    
    parameter W_WIDTH = 8;    
    parameter S_WIDTH = 5;    
    parameter F_WIDTH = 6;
    parameter U_WIDTH = 3;
    parameter n_WIDTH = 3;
    parameter p_WIDTH = 5;
    parameter q_WIDTH = 3;
    
    parameter IFMAP_SPAD_DEPTH  = 12;
    parameter FILTER_SPAD_DEPTH = 224;
    parameter PSUM_SPAD_DEPTH   = 24;
    
    localparam W_MAX = 227;
    localparam S_MAX = 11;
    localparam F_MAX = 55; 
    localparam U_MAX = 4;
	localparam n_MAX = 4;
    localparam p_MAX = 16;
    localparam q_MAX = 4;
    
    localparam IFMAP_MEM_SIZE  = n_MAX * W_MAX * q_MAX;
    localparam FILTER_MEM_SIZE = (p_MAX * q_MAX * S_MAX + 3) / 4;
    localparam PSUM_MEM_SIZE   = (p_MAX * n_MAX * F_MAX + 3) / 4;
    
    parameter LAYER_W = 227;
    parameter LAYER_S = 11;
    parameter LAYER_F = 55; 
    parameter LAYER_U = 4;
	parameter LAYER_n = 1;
    parameter LAYER_p = 16;
    parameter LAYER_q = 1;
  
    reg  clk;
    reg  reset;
    reg  enable;
    reg  configure;
    wire busy;
	
    reg [W_WIDTH - 1:0] W;    
    reg [S_WIDTH - 1:0] S;    
    reg [F_WIDTH - 1:0] F;
    reg [U_WIDTH - 1:0] U;
    reg [n_WIDTH - 1:0] n;    
    reg [p_WIDTH - 1:0] p;      
    reg [q_WIDTH - 1:0] q;  
 
    reg  [DATA_WIDTH_IFMAP-1:0] ifmap_mem [0:IFMAP_MEM_SIZE - 1];  
	reg  [DATA_WIDTH_IFMAP-1:0] ifmap;
    reg                         push_ifmap;
	wire                        ifmap_fifo_full;
    
    reg  [DATA_WIDTH_FILTER-1:0] filter_mem [0:FILTER_MEM_SIZE - 1];  
	reg  [DATA_WIDTH_FILTER-1:0] filter;
    reg                          push_filter;
	wire                         filter_fifo_full;
	
	reg	 [DATA_WIDTH_PSUM-1:0] ipsum_mem [0:PSUM_MEM_SIZE - 1];
	reg  [DATA_WIDTH_PSUM-1:0] ipsum;
    reg                        push_ipsum;
	wire                       ipsum_fifo_full;

    reg  [DATA_WIDTH_PSUM-1:0] expected_output [0:PSUM_MEM_SIZE - 1];
    wire [DATA_WIDTH_PSUM-1:0] opsum; 
    reg                        pop_opsum;
    wire                       opsum_fifo_empty;
    
    always #(CLK_PERIOD/2.0) clk = ~clk;

    PE_wrapper #(
        .DATA_WIDTH(DATA_WIDTH),
        
        .DATA_WIDTH_IFMAP(DATA_WIDTH_IFMAP),
        .DATA_WIDTH_FILTER(DATA_WIDTH_FILTER),
        .DATA_WIDTH_PSUM(DATA_WIDTH_PSUM),
        
        .IFMAP_FIFO_DEPTH(IFMAP_FIFO_DEPTH),
        .FILTER_FIFO_DEPTH(FILTER_FIFO_DEPTH),
        .PSUM_FIFO_DEPTH(PSUM_FIFO_DEPTH),
        
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
    ) DUT (
        .clk(clk),
        .reset(reset),
        
        .enable(enable),
        .configure(configure),
        .busy(busy),
           
        .W(W),
        .S(S),
        .F(F),
        .U(U),
        .n(n),
        .p(p),
        .q(q), 
		
        .push_ifmap(push_ifmap),
        .ifmap(ifmap),
        .ifmap_fifo_full(ifmap_fifo_full),
        
        .push_filter(push_filter),
        .filter(filter), 
        .filter_fifo_full(filter_fifo_full), 
               
        .push_ipsum(push_ipsum),
        .ipsum(ipsum),
        .ipsum_fifo_full(ipsum_fifo_full),
        
        .pop_opsum(pop_opsum),
        .opsum(opsum),
        .opsum_fifo_empty(opsum_fifo_empty)
    );
    
    initial begin
        // Load input data
        $readmemb("ifmap_data.mem", ifmap_mem);
        $readmemb("filter_data.mem", filter_mem);
        $readmemb("ipsum_data.mem", ipsum_mem);
        $readmemb("expected_output.mem", expected_output);
    
		intialize_DUT();
        assert_reset();
        cfg(LAYER_W, LAYER_S, LAYER_F, LAYER_U, LAYER_n, LAYER_p, LAYER_q);
        
        fork
            push_ifmap_data();
            push_filter_data();
            push_ipsum_data();
            check_opsum_data();
        join
        
        $display("--------------------------------- Summary ---------------------------------");
        $display("Total Match: %0d/%0d", pass_count, (LAYER_p * LAYER_n * LAYER_F + 3) / 4);
        $display("Total Mismatch: %0d/%0d", error_count, (LAYER_p * LAYER_n * LAYER_F + 3) / 4);
        $stop;
	end
	
    task automatic push_ifmap_data;
        begin
            for (int i = 0; i < LAYER_n * LAYER_W * LAYER_q; i = i + 1) begin
                wait(!ifmap_fifo_full);
                wait_cycles(1);
                ifmap = ifmap_mem[i];
                push_ifmap = 1;
                wait_cycles(1);
                push_ifmap = 0;
                ifmap = 0;
            end
        end
    endtask

    task automatic push_filter_data;
        begin
            for (int j = 0; j < (LAYER_p * LAYER_q * LAYER_S + 3) / 4; j = j + 1) begin
                wait(!filter_fifo_full); 
                wait_cycles(1);
                filter = filter_mem[j];
                push_filter = 1;
                wait_cycles(1);
                push_filter = 0;
                filter = 0;
            end
        end
    endtask

    task automatic push_ipsum_data;
        begin
            for (int k = 0; k < (LAYER_p * LAYER_n * LAYER_F + 3) / 4; k = k + 1) begin
                wait(DUT.ipsum_fifo_empty);
                wait_cycles(1);
                ipsum = ipsum_mem[k];
                push_ipsum = 1'b1;
                wait_cycles(1);
                push_ipsum = 1'b0;
                ipsum = 0;
            end
        end
    endtask

    task automatic check_opsum_data;
        begin
            for (int m = 0; m < (LAYER_p * LAYER_n * LAYER_F + 3) / 4; m = m + 1) begin
                wait(!opsum_fifo_empty);
                wait_cycles(1);
                pop_opsum = 1'b1;
                
                if (opsum == expected_output[m]) begin
                    pass_count++;
                    $display("Correct at index %0d: Expected %h, Got %h at time = %0t", m, expected_output[m], opsum, $time);
                end else begin
                    error_count++;
                    $display("Mismatch at index %0d: Expected %h, Got %h at time = %0t", m, expected_output[m], opsum, $time);
                end
                
                wait_cycles(1);
                pop_opsum = 1'b0;
            end
        end
    endtask


	
	task intialize_DUT;
		begin
            clk         = 1'b0;
            reset       = 1'b0;
            enable      = 1'b1;
            configure   = 1'b0;
            push_ifmap  = 1'b0;
            push_filter = 1'b0;
            push_ipsum  = 1'b0;
            pop_opsum   = 1'b0; 
		end
	endtask
	
	task wait_cycles;
        input integer num_cycles;
        begin
            repeat(num_cycles) @(posedge clk);
        end
    endtask
	
	task assert_reset;
        begin
            wait_cycles(1); 
            reset = 1'b1;
            wait_cycles(1);      
            reset = 1'b0; 
        end
    endtask
	
    task cfg;
        input [W_WIDTH - 1:0] cfg_W;
        input [S_WIDTH - 1:0] cfg_S;
        input [F_WIDTH - 1:0] cfg_F;
        input [U_WIDTH - 1:0] cfg_U;
        input [n_WIDTH - 1:0] cfg_n;
        input [p_WIDTH - 1:0] cfg_p;
        input [q_WIDTH - 1:0] cfg_q;        
        begin
            W = cfg_W; S = cfg_S; F = cfg_F; U = cfg_U; n = cfg_n; p = cfg_p; q = cfg_q;
            wait_cycles(1);
            configure = 1'b1; 
            wait_cycles(1);      
            configure = 1'b0;
            W = 0; S = 0; F = 0; U = 0; n = 0; p = 0; q = 0; 
        end
    endtask
	
endmodule