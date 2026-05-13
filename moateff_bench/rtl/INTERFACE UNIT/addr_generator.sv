module address_generator #(parameter ADDR_WIDTH = 16)
(
    input wire        core_clk,
    input wire        reset,
	input wire        Direct_Back_Path,
    input wire        enable,
	input wire        transfer,
    input wire 		  [ADDR_WIDTH-1:0] base_address,  
    input wire        increment,
    output wire       [ADDR_WIDTH-1:0] address       // Output address
);

		// State Encoding
		localparam IDLE      = 1'b0;
		localparam COUNTING  = 1'b1;

		reg state_crnt, state_nxt;
		reg [ADDR_WIDTH-1:0] address_crnt, address_nxt;

		reg increment_prev;  
		wire increment_falling = (increment_prev && !increment);

		// State Transition
		always @(negedge core_clk or posedge reset) 
		begin
			if (reset)
			begin
				state_crnt      <= IDLE;
				address_crnt    <= 0;
				increment_prev  <= 0;
			end 
			else 
			begin
				state_crnt      <= state_nxt;
				address_crnt    <= address_nxt;
				increment_prev  <= increment;  
			end
		end

		// Next-State and Output Logic
		always @(*) begin
			state_nxt   = state_crnt;
			address_nxt = address_crnt;

			case (state_crnt)
				IDLE: 
				begin
					if (enable && transfer) 
					begin
						address_nxt = base_address;
						state_nxt   = COUNTING;
					end
				end

				COUNTING: 
				begin
					if (transfer)
					begin
						if (!Direct_Back_Path)
						begin
							if (enable && increment) 
							begin
								address_nxt = address_crnt + 1;
							end
							else if (increment_falling)
							begin
								address_nxt = base_address;
							end
						end
						
						else 
						begin
							if (enable && increment) 
							begin
								address_nxt = address_crnt + 1;
							end
							else
							begin
								address_nxt = address_crnt;
							end
						end
					end
					else
					begin
						address_nxt = 0;
						state_nxt = IDLE;
					end
				end
				
				default: state_nxt = IDLE;
			endcase
		end

		assign address = address_nxt << 2;  

endmodule
