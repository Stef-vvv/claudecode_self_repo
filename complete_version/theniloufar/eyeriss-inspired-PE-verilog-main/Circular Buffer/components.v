module counter
    #(parameter DEPTH)
    (input clk, rst, cnt, input [3:0] PAR_IN, output reg [3:0] count_out);
    always @(posedge clk) begin
        if (rst)
            count_out <= 4'b0;
        else if (cnt)
            count_out <= (count_out + PAR_IN) % DEPTH;
    end
endmodule

module comparator #(parameter N) (input sig, input [N-1:0] a, b, output gt, eq);
    assign gt = (sig) ? (b >= a) : (b > a);
    assign eq = (a == b);
endmodule

module mux #(parameter N) (input [N-1:0] a, b, input src, output [N-1:0] out);
    assign out = (~src) ? a : b;
endmodule

module adder(input [3:0] a, b, output [4:0] out);
    assign out = a + b;
endmodule

module buffer 
    #(parameter SIZE, 
    parameter DEPTH,
    parameter PAR_WRITE,
    parameter PAR_READ)
    (input clk, rst, wen, input [3:0] waddr, raddr, input [(PAR_WRITE * SIZE)-1:0] din, output reg [(PAR_READ * SIZE)-1:0] dout);
    reg [SIZE-1:0] memory [0:DEPTH-1];
    integer i;

    // Write operation
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset memory content if needed
            for (i = 0; i < DEPTH; i = i + 1)
                memory[i] <= 0;
        end else if (wen) begin
            // Parallel write operation
            for (i = 0; i < PAR_WRITE; i = i + 1) begin
                memory[(waddr + i) % DEPTH] <= din[(i * SIZE) +: SIZE];
            end
        end
    end

    // Read operation (asynchronous)
    always @(*) begin
        // Parallel read operation
            for (i = 0; i < PAR_READ; i = i + 1) begin
            dout[((PAR_READ - i - 1) * SIZE) +: SIZE] <= memory[(raddr + i) % DEPTH]; // Read each segment into `dout`
        end
    end
endmodule

module determiner
    (input sig, input [3:0] PAR_IN, write_ptr, read_ptr, DEPTH, output out);
    wire [4:0] write_plus_depth, read_plus_depth, depth_mux, mux_out, PAR_mux, ptr_mux, write_plus_PAR, read_plus_PAR;
    wire [3:0] ptr_mux_in;
    wire xor_out, gt, eq, gt_final, eq_final;

    // addition
    adder add1(read_ptr, DEPTH, read_plus_depth);
    adder add2(write_ptr, DEPTH, write_plus_depth);
    adder add3(read_ptr, PAR_IN, read_plus_PAR);
    adder add4(write_ptr, PAR_IN, write_plus_PAR);

    xor(xor_out, sig, gt);

    // muxs
    mux #(4) m1(read_ptr, write_ptr, sig, ptr_mux_in);
    assign ptr_mux = {1'b0, ptr_mux_in};
    mux #(5) m2(read_plus_depth, write_plus_depth, sig, depth_mux);
    mux #(5) m3(ptr_mux, depth_mux, xor_out, mux_out);
    mux #(5) m4(write_plus_PAR, read_plus_PAR, sig, PAR_mux);

    // compares
    comparator #(4) c1(sig, read_ptr, write_ptr, gt, eq);
    comparator #(5) c2(sig, PAR_mux, mux_out, gt_final, eq_final);

    assign out = (eq) ? (~sig) : gt_final;
endmodule