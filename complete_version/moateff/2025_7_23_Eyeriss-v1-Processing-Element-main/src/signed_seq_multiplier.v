module signed_seq_mul
#(
    parameter PIXEL_WIDTH = 16
)(
    input wire clk, reset, enable,
    input wire signed [PIXEL_WIDTH-1:0] a,
    input wire signed [PIXEL_WIDTH-1:0] b,
    
    output wire signed [2*PIXEL_WIDTH-1:0] product
);
    localparam PIXEL_HALF_WIDTH = PIXEL_WIDTH/2;
    
    reg  [PIXEL_WIDTH-1:0] 		abs_a, abs_b;
    reg  						sign_a, sign_b, final_sign, final_sign_reg;
    wire [2*PIXEL_WIDTH-1:0] 	abs_product;
     
    reg [PIXEL_HALF_WIDTH - 1:0] a_low, a_high;
    
    
    wire  [PIXEL_HALF_WIDTH + PIXEL_WIDTH - 1:0] partial_1;
    reg   [PIXEL_HALF_WIDTH + PIXEL_WIDTH - 1:0] partial_1_reg;

    wire [PIXEL_HALF_WIDTH + PIXEL_WIDTH - 1 : 0] partial_2;
	wire [2 * PIXEL_WIDTH - 1 : 0]                partial_2_concatinated;
	reg  [2 * PIXEL_WIDTH - 1 : 0]                partial_2_reg;

    always @(*) begin
        sign_a = a[PIXEL_WIDTH-1];  // Extract MSB (sign bit)
        sign_b = b[PIXEL_WIDTH-1];  // Extract MSB (sign bit)
        // Determine the final sign
        final_sign = sign_a ^ sign_b; 
        // Convert to absolute values
        abs_a = sign_a ? -a : a;
        abs_b = sign_b ? -b : b;
        // Extract low and high part
        a_low  = abs_a[PIXEL_HALF_WIDTH - 1:0];
        a_high = abs_a[PIXEL_WIDTH - 1 : PIXEL_HALF_WIDTH];           
    end
    
    wallace_tree_multiplier #(
            .in1_width(PIXEL_HALF_WIDTH),
            .in2_width(PIXEL_WIDTH)
        ) mul_low (
            .in1(a_low),
            .in2(abs_b),
            .out(partial_1)
        );
    
        wallace_tree_multiplier #(
            .in1_width(PIXEL_HALF_WIDTH), 
            .in2_width(PIXEL_WIDTH)
        ) mul_high (
            .in1(a_high),
            .in2(abs_b),
            .out(partial_2)
        );
        assign partial_2_concatinated = {{PIXEL_HALF_WIDTH{1'b0}}, partial_2};
        
        always @(negedge clk or posedge reset) begin
                if (reset) begin
                    partial_1_reg  <= 'b0;
                    partial_2_reg  <= 'b0;
					final_sign_reg <= 'b0;
                end else begin
                    if(enable) begin
                        partial_1_reg <= partial_1;
                        partial_2_reg <= (partial_2_concatinated << PIXEL_HALF_WIDTH);
						final_sign_reg <= final_sign;
                    end else begin
                        partial_1_reg  <= 'b0;
                        partial_2_reg  <= 'b0;
						final_sign_reg <= 'b0;
                    end
                end
            end
  
        cla #(
            .width(2*PIXEL_WIDTH)
        ) cla (
        
            .x({{PIXEL_HALF_WIDTH{1'b0}}, partial_1_reg}),
            .y(partial_2_reg),
            
            .sum(abs_product)
        );
        
		assign product = final_sign_reg ? -abs_product : abs_product;  
        
        
endmodule
