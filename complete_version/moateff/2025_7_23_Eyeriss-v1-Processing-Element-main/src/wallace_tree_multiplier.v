module wallace_tree_multiplier #(
    parameter in1_width = 4,
    parameter in2_width = 4
)(
    input  wire [in1_width - 1 : 0] in1,
    input  wire [in2_width - 1 : 0] in2,
	
	output wire [in1_width + in2_width - 1 : 0] out
);

    /*============== Generate Partial Products ==============*/
    wire [in1_width + in2_width - 1 : 0] partial_products [in2_width - 1 : 0];
    genvar i;
    generate
        for (i = 0; i < in2_width; i = i + 1) begin : PARTIAL_PRODUCTS
            assign partial_products[i] = in2[i] ? (in1 << i) : {(in1_width + in2_width){1'b0}};
        end
    endgenerate

    /*============== Tree Reduction using Carry-Save Adders ==============*/
    wire [in1_width + in2_width - 1 : 0] sum [in2_width - 1 : 0];
    wire [in1_width + in2_width - 1 : 0] carry [in2_width - 1 : 0];

    assign sum[0] = partial_products[0];
    assign carry[0] = {(in1_width + in2_width){1'b0}};

    generate
        for (i = 1; i < in2_width; i = i + 1) begin : TREE_REDUCTION
            assign sum[i] = sum[i-1] ^ partial_products[i] ^ carry[i-1];
            assign carry[i] = ((sum[i-1] & partial_products[i]) | 
                               (sum[i-1] & carry[i-1]) | 
                               (partial_products[i] & carry[i-1])) << 1;
        end
    endgenerate

    /*============== Final Addition using a Carry Lookahead Adder (CLA) ==============*/ 
    wire [in1_width + in2_width - 1 : 0] final_sum;

    cla #(
		.width(in1_width + in2_width)
	) cla (
        .x(sum[in2_width - 1]),
        .y(carry[in2_width - 1]),
		.sum(final_sum)
    );

    assign out = final_sum;

endmodule
