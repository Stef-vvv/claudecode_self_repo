module controller #(parameter ADDR_WIDTH = 20)
(
	input wire 	core_clk,
	input wire 	link_clk,
	input wire 	core_reset, 
	input wire 	link_reset,
	input wire 	[ADDR_WIDTH-1:0] words_num,          // based on worst case (conv4 filters 221184 words) 
	input wire 	[1:0] ifmap_filter_bias_transfer,
	input wire 	start_forward,
	input wire 	valid_from_DRAM,
	input wire 	start_backward,            // start signal from GLB to transfer data GLB ---> DRAM (only one time (after conv5 finished))
	input wire 	wfull,
	output reg 	Direct_Back_Path,
	output reg 	[1:0] ifmap_filter,
	output reg 	ifmap_bias,
	output reg 	read_from_DRAM,
	output reg 	rinc_to_GLB,
	output reg 	read_from_GLB,
	output reg 	rinc_to_DRAM,
	output reg 	DRAM_w_en,
	output reg 	back_transfer_done,ifmap_transfer_done,filter_transfer_done,bias_transfer_done,
	output reg 	increment,
	output reg  transfer
);

	localparam [1:0]  		idle 				   = 2'b00, 
							forward_transfer       = 2'b01,
							backward_transfer      = 2'b11,
							wait_state             = 2'b10;
						 
						 
	reg [ADDR_WIDTH-1:0] words_num_forward_crnt,words_num_forward_nxt;
	reg [ADDR_WIDTH-1:0] words_num_crnt,words_num_nxt;                      // backward path with core clock
	reg [3:0] wait_count_crnt, wait_count_nxt;
	reg GLB_wait_crnt,GLB_wait_nxt,times_crnt,times_nxt;
	reg ifmap_wait_crnt,ifmap_wait_nxt, filter_wait_crnt,filter_wait_nxt, bias_wait_crnt,bias_wait_nxt;
	reg transfer_GLB_crnt,transfer_GLB_nxt;
	
	// states 
	
	reg [1:0] current_state, next_state;
	
	always @(posedge core_clk, posedge core_reset)
	begin
		if (core_reset)
		begin
			current_state <= idle;
			words_num_crnt <= 0;
			wait_count_crnt <= 0;
			ifmap_wait_crnt <= 0;
			filter_wait_crnt <= 0;
			bias_wait_crnt <= 0;
			GLB_wait_crnt <= 0;
			transfer_GLB_crnt <= 0;
			times_crnt <= 0;
		end

		else
		begin
			current_state <= next_state;
			wait_count_crnt <= wait_count_nxt;
			ifmap_wait_crnt <= ifmap_wait_nxt;
			filter_wait_crnt <= filter_wait_nxt;
			bias_wait_crnt <= bias_wait_nxt;
			GLB_wait_crnt <= GLB_wait_nxt;
			words_num_crnt <= words_num_nxt;
			transfer_GLB_crnt <= transfer_GLB_nxt;
			times_crnt <= times_nxt;
		end
	end
	
	always @(posedge link_clk, posedge link_reset)
	begin
		if (link_reset)
		begin
			words_num_forward_crnt <= 0;
		end

		else
		begin
			words_num_forward_crnt <= words_num_forward_nxt;
		end
	end
	
	
	// state transition and output logic
	
	always @(*)
	begin
	
	// default value for the outputs
	Direct_Back_Path = 0;
	ifmap_filter = 0;
	ifmap_bias = 0;
	read_from_DRAM = 0;
	rinc_to_GLB = 0;
	read_from_GLB = 0;
	rinc_to_DRAM = 0;
	DRAM_w_en = 0;
	back_transfer_done = 0;
	ifmap_transfer_done = 0;
	filter_transfer_done = 0;
	bias_transfer_done = 0;
	increment = 0;
	transfer = 0;

	// default value for some signals
	wait_count_nxt = wait_count_crnt;
	ifmap_wait_nxt = ifmap_wait_crnt;
	filter_wait_nxt = filter_wait_crnt;
	bias_wait_nxt = bias_wait_crnt;
	GLB_wait_nxt = GLB_wait_crnt;
	times_nxt = times_crnt;
	words_num_nxt = words_num_crnt;
	words_num_forward_nxt = words_num_forward_crnt;
	transfer_GLB_nxt = transfer_GLB_crnt;
	
		case (current_state)
			idle:
			begin
				Direct_Back_Path = 0;
				ifmap_filter = 0;
				ifmap_bias = 0;
				read_from_DRAM = 0;
				rinc_to_GLB = 0;
				read_from_GLB = 0;
				rinc_to_DRAM = 0;
				DRAM_w_en = 0;
				back_transfer_done = 0;
				ifmap_transfer_done = 0;
				filter_transfer_done = 0;
				bias_transfer_done = 0;
				words_num_nxt = 0;
				words_num_forward_nxt = 0;
				transfer = 0;
				
				if (start_forward)
					next_state = forward_transfer;
				
				else if (start_backward)
					next_state = backward_transfer;
				
				else
					next_state = idle;
			end
			
			
			forward_transfer:
			begin
				transfer = 1;
				case(ifmap_filter_bias_transfer)
				
					// path from DRAM ----> ifmap GLB
					2'b00:
					begin
						increment = 1;
						Direct_Back_Path = 0;
						ifmap_filter = 2'b00;
						ifmap_bias = 1;
						read_from_DRAM = 1;
					    rinc_to_GLB = 1;
						
						if (words_num_forward_crnt == words_num - 1)        // reached to the maximum 
						begin
							words_num_forward_nxt = 0;
							ifmap_wait_nxt = 1;
							next_state = wait_state;          
						end
						
						else
						begin
							if (valid_from_DRAM)
							begin
								words_num_forward_nxt = words_num_forward_crnt + 1;
								
							end
							else
								words_num_forward_nxt = words_num_forward_crnt;
								
							ifmap_wait_nxt = 0;
							next_state = forward_transfer;
						end		
					end
					
					// path from DRAM ----> filter GLB
					2'b01:
					begin
						increment = 1;
						Direct_Back_Path = 0;
						ifmap_filter = 2'b10;
						read_from_DRAM = 1;
						rinc_to_GLB = 1;
						
						if (words_num_forward_crnt == words_num - 1)         // reached to the maximum
						begin
							words_num_forward_nxt = 0;
							filter_wait_nxt = 1;
							next_state = wait_state;
						end
						
						else
						begin
							if (valid_from_DRAM)
							begin
								words_num_forward_nxt = words_num_forward_crnt + 1;
								
							end
							else
								words_num_forward_nxt = words_num_forward_crnt;
								
							filter_wait_nxt = 0;
							next_state = forward_transfer;
						end
					end

					// path from DRAM ----> bias GLB
					2'b10:
					begin
						increment = 1;
						Direct_Back_Path = 0;
						ifmap_filter = 2'b01;
						read_from_DRAM = 1;
						rinc_to_GLB = 1;
						
						if (words_num_forward_crnt == words_num - 1)         // reached to the maximum
						begin
							words_num_forward_nxt = 0;
							bias_wait_nxt = 1;
							next_state = wait_state;
						end
						
						else
						begin
							if (valid_from_DRAM)
							begin
								words_num_forward_nxt = words_num_forward_crnt + 1;
								
							end
							else
								words_num_forward_nxt = words_num_forward_crnt;
								
							bias_wait_nxt = 0;
							next_state = forward_transfer;
						end
					end
					
					default:
					begin
						next_state = idle;
						Direct_Back_Path = 0;
						ifmap_filter = 0;
						ifmap_bias = 0;
						read_from_DRAM = 0;
						rinc_to_GLB = 0;
						increment = 0;
						words_num_forward_nxt = 0;
						bias_wait_nxt = 0;
					end				
				endcase
			end
			
			
			// path from output maxpooling GLB -----> DRAM
			backward_transfer:
			begin
				transfer = 1;
				if (transfer_GLB_crnt)            // starting transfer 
				begin
					if (words_num_crnt == words_num - 1) // loop for reading from GLB           // with core clock
					begin
						increment = 0;
						read_from_GLB = 0;
						if (words_num_forward_crnt == words_num - 1)        // loop for writing in DRAM     // will increase with the link clock
						begin
							words_num_forward_nxt = 0;
							rinc_to_DRAM = 1;
							DRAM_w_en = 1;
							Direct_Back_Path = 1;
							GLB_wait_nxt = 1;
							next_state = wait_state;
						end
						else
						begin
							words_num_forward_nxt = words_num_forward_crnt + 1;
							Direct_Back_Path = 1;
							rinc_to_DRAM = 1;
							DRAM_w_en = 1;
							next_state = backward_transfer;
						end
					end
					
					else
					begin
						Direct_Back_Path = 1;
						read_from_GLB = 1;
						rinc_to_DRAM = 1;
						DRAM_w_en = 1;
						if (!wfull)
						begin
							increment = 1;
							words_num_nxt = words_num_crnt + 1;
						end
						else
						begin
							increment = 0;
							words_num_nxt = words_num_crnt;
						end
						words_num_forward_nxt = words_num_forward_crnt + 1;
						next_state = backward_transfer;
					end
				
				end
				
				else               // going to first wait state // will not do anything just waiting till clock switching
				begin
					increment = 0;
					Direct_Back_Path = 1;
					GLB_wait_nxt = 1;
					times_nxt = 0;
					words_num_forward_nxt = 0;
					words_num_nxt = 0;
					next_state = wait_state;
				end
			end
		
		
		
			wait_state:
			begin
				transfer = 1;
				if (ifmap_wait_crnt)
				begin
					increment = 1;
					Direct_Back_Path = 0;
					ifmap_filter = 2'b00;
					read_from_DRAM = 0;
				
					if (wait_count_crnt == 6)
					begin
						wait_count_nxt = 0;
						next_state = idle;
						ifmap_wait_nxt = 0;
						ifmap_filter = 0;
						ifmap_bias = 0;
						rinc_to_GLB = 0;
						ifmap_transfer_done = 1;
						words_num_forward_nxt = 0;
						increment = 0;
					end
					
					else
					begin
						wait_count_nxt = wait_count_crnt + 1;
						next_state = wait_state;
						ifmap_wait_nxt = 1;
						ifmap_bias = 1;
						rinc_to_GLB = 1;
						ifmap_transfer_done = 0;
						words_num_forward_nxt = 0;
					end				
				end
				
				else if (filter_wait_crnt)
				begin
					increment = 1;
					Direct_Back_Path = 0;
					ifmap_filter = 2'b10;
					read_from_DRAM = 0;
					
					if (wait_count_crnt == 6)
					begin
						wait_count_nxt = 0;
						next_state = idle;
						filter_wait_nxt = 0;
						rinc_to_GLB = 0;
						ifmap_filter = 0;
						filter_transfer_done = 1;
						words_num_forward_nxt = 0;
						increment = 0;
					end
					
					else
					begin
						wait_count_nxt = wait_count_crnt + 1;
						next_state = wait_state;
						filter_wait_nxt = 1;
						rinc_to_GLB = 1;
						filter_transfer_done = 0;
						words_num_forward_nxt = 0;
					end				
				end
				
				else if (bias_wait_crnt)
				begin
					increment = 1;
					Direct_Back_Path = 0;
					ifmap_filter = 2'b01;
					read_from_DRAM = 0;
					
					if (wait_count_crnt == 6)
					begin
						wait_count_nxt = 0;
						next_state = idle;
						bias_wait_nxt = 0;
						rinc_to_GLB = 0;
						ifmap_filter = 0;
						bias_transfer_done = 1;
						words_num_forward_nxt = 0;
						increment = 0;
					end
					
					else
					begin
						wait_count_nxt = wait_count_crnt + 1;
						next_state = wait_state;
						bias_wait_nxt = 1;
						rinc_to_GLB = 1;
						bias_transfer_done = 0;
						words_num_forward_nxt = 0;
					end				
				end
				
				else if (GLB_wait_crnt)
				begin
					case (times_crnt)
						1'b0:
						begin
							if (wait_count_crnt == 6)
							begin
								wait_count_nxt = 0;
								GLB_wait_nxt = 0;
								Direct_Back_Path = 1;
								read_from_GLB = 1;                                        	                                                	
								rinc_to_DRAM = 1; 
								DRAM_w_en = 1;
								transfer_GLB_nxt = 1;
								times_nxt = 1;
								next_state = backward_transfer;
								words_num_forward_nxt = 0;
							end
							
							else
							begin
								wait_count_nxt = wait_count_crnt + 1;
								GLB_wait_nxt = 1;
								Direct_Back_Path = 1;
								read_from_GLB = 0;                                        	                                                	
								rinc_to_DRAM = 0;
								DRAM_w_en = 0;
								transfer_GLB_nxt = 0;
								words_num_forward_nxt = 0;
								next_state = wait_state;
							end	
						end
						1'b1:                                      // finish receiving
						begin
							if (wait_count_crnt == 12)
							begin
								increment = 0;
								wait_count_nxt = 0;
								GLB_wait_nxt = 0;
								Direct_Back_Path = 0;
								read_from_GLB = 0;                                        	                                                	
								rinc_to_DRAM = 1;
								DRAM_w_en = 1;
								transfer_GLB_nxt = 0;
								times_nxt = 0;
								back_transfer_done = 1;
								next_state = idle;
							end
							
							else
							begin
								wait_count_nxt = wait_count_nxt + 1;
								GLB_wait_nxt = 1;
								Direct_Back_Path = 1;
								read_from_GLB = 0;                                        	                                                	
								rinc_to_DRAM = 1; 
								DRAM_w_en = 1;
								transfer_GLB_nxt = 0;
								next_state = wait_state;
								increment = 0;
							end	
						end
					endcase
				end
				
				else
				begin
					next_state = idle;
					wait_count_nxt = 0;
					ifmap_wait_nxt = 0;
					filter_wait_nxt = 0;
					bias_wait_nxt = 0;
					GLB_wait_nxt = 0;
					words_num_forward_nxt = 0;
					words_num_nxt = 0;
				end			
			end
			
			default:
			begin
				next_state = idle;
				Direct_Back_Path = 0;
				ifmap_filter = 0;
				ifmap_bias = 0;
				read_from_DRAM = 0;
				rinc_to_GLB = 0;
				read_from_GLB = 0;
				rinc_to_DRAM = 0;
				DRAM_w_en = 0;
				back_transfer_done = 0;
				ifmap_transfer_done = 0;
				filter_transfer_done = 0;
				bias_transfer_done = 0;
				transfer = 0;
				words_num_forward_nxt = 0;
				words_num_nxt = 0;
			end		
		endcase
	end
	
	
endmodule
