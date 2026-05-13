module filter_read_cnt 
        #(parameter SRAM_SIZE = 4,
        parameter F_SIZE = $clog2(SRAM_SIZE)) 
        (input clk,
        input rst,
        input en,
        input [F_SIZE-1:0] filter_size,
        output co,
        output reg [F_SIZE-1:0] dout);

    // necessary wires
    reg [F_SIZE-1:0] val;
    reg [F_SIZE-1:0] res_out;
    
    // assign co value
    assign co = (dout == res_out); 

    // 
    always @(*) begin
        // check for zero filter size
        if (filter_size != 0) begin
            val = ((SRAM_SIZE / filter_size) * filter_size);
            res_out = (val != 0) ?  val - 1 : {F_SIZE{1'b1}}; 
        end
        // assign result to ones
        else
            res_out =  {F_SIZE{1'b1}}; 
    end

    // count up
    always @(posedge clk) begin
        // insert zeros if rst is toggled
        if (rst)
            dout <= {F_SIZE{1'b0}}; 
        else if (en)
                dout <= dout + 1;         
    end
endmodule

module stride_cnt #(parameter IFMAP_DATA_WIDTH = 4,parameter FILTER_DATA_WIDTH)
        (input clk,
        input rst,
        input en,
        input reset_stride,
        input input_done,
        input [IFMAP_DATA_WIDTH-1:0] stride, input_out,
        input [FILTER_DATA_WIDTH-1:0] filter_size,
        output co,
        output reg [IFMAP_DATA_WIDTH-1:0] dout);

    // utility wires
    wire [1:0] co_middle;
    wire [IFMAP_DATA_WIDTH-1:0] sum;
    wire [IFMAP_DATA_WIDTH-1:0] f_size;

    // assigns
    // assign the next start point
    assign {co_middle, sum} = dout + (stride - 1) + f_size; 
    // assign filter size
    assign f_size = {{(IFMAP_DATA_WIDTH - FILTER_DATA_WIDTH){1'b0}}, filter_size};
    // assign co
    assign co = (((co_middle > 2'b00) || (sum > input_out)) && input_done) ? 1'b1 : 1'b0;

    always @(posedge clk) begin
        // if any of the resets, insert zeros
        if (rst || reset_stride)
            dout <= {IFMAP_DATA_WIDTH{1'b0}}; 
        else begin
            // count up to the number of strides
            if (en)
                dout <= dout + stride; 
        end            
    end
endmodule

module write_cnt 
        # (parameter WIDTH = 4,
        parameter SIZE = 4) 
        (input clk,
        input rst,
        input en,
        input filter_done,
        input [WIDTH-1:0] filter_size,
        output co,
        output reg [WIDTH-1:0] dout);

    reg [WIDTH-1:0] temp;
    // qunatify temp val
    always @(*) begin
        if (filter_size != 0) begin
            temp = (SIZE / filter_size);
        end
    end

    // assign carry out based on temp and dout
    assign co = (filter_done && (dout == temp)); 

    always @(posedge clk) begin
        // if reset, fill with zeros
        if (rst)
            dout <= {WIDTH{1'b0}}; 
        else begin
            if (en)
                dout <= dout + 1; 
        end            
    end
endmodule

module filter_num_cnt 
    #(parameter WIDTH = 4)
    (input clk, 
    input rst,
    input en,
    input [WIDTH-1:0] val,
    output co,
    output reg [WIDTH-1:0] dout);

    // assign co
    assign co = &dout;

    // count up
    always @(posedge clk) begin
        // if reset is toggled, fill with zeros
        if (rst)
            dout <= {WIDTH{1'b0}}; 
        else begin
            if (en)
                dout <= dout + val; 
        end            
    end
endmodule

module filter_inner_cnt 
    #(parameter WIDTH = 4) 
    (input clk,
    input rst,
    input ld,
    input en,
    input reset_in,
    input [(2*WIDTH)-1:0] din,
    input [WIDTH-1:0] filter_size,
    output co,
    output reg [(2*WIDTH)-1:0] dout);

    // utility wires
    wire [(2*WIDTH)-1:0] temp;

    // assigns
    // assign carry out
    assign co = (dout == temp);
    // assign temp to the filter size and concatenate it
    assign temp = {{WIDTH{1'b0}}, filter_size};

    always @(posedge clk) begin
        // if any of the resets are toggled, fill with zeros
        if (rst || reset_in)
            dout <= {(2 * WIDTH){1'b0}}; 
        // count up
        else begin
            if (ld)
                dout <= din; 
            else if (en)
                dout <= dout + 1; 
        end            
    end
endmodule

module data_read_cnt 
    #(parameter WIDTH = 4)
    (input clk,
    input rst,
    input en,
    output co,
    output reg [WIDTH-1:0] dout);

    // normal counter
    always @(posedge clk) begin
        if (rst)
            dout <= {WIDTH{1'b0}}; 
        else begin
            if (en)
                dout <= dout + 1; 
        end            
    end

    // carry out    
    assign co = &dout; 

endmodule
