module SRAM_File #(
    parameter WIDTH = 4,
    parameter SIZE = 4, 
    parameter ADDR_WIDTH = $clog2(SIZE)) 
    (input clk,
    input ren, 
    input wen,
    input chip_en,
    input [ADDR_WIDTH-1:0] r_addr,
    input [ADDR_WIDTH-1:0] w_addr, 
    input [WIDTH-1:0] din,
    output reg [WIDTH-1:0] dout);

    // instanciate memroy
    reg [WIDTH-1 : 0] mem [0 : SIZE-1];

    initial $readmemb ("memory.mem", mem);

    always @(posedge clk) begin
        if (chip_en) begin
            if (wen)
                mem[w_addr] <= din;
            if (ren)
                dout <= mem[r_addr];
        end
    end

endmodule

module SRAM #(
    parameter WIDTH = 4,
    parameter SIZE = 4, 
    parameter ADDR_WIDTH = $clog2(SIZE)) 
    (input clk,
    input ren, 
    input wen,
    input chip_en,
    input [ADDR_WIDTH-1:0] r_addr,
    input [ADDR_WIDTH-1:0] w_addr, 
    input [WIDTH-1:0] din,
    output reg [WIDTH-1:0] dout);

    // instanciate memroy
    reg [WIDTH-1 : 0] mem [0 : SIZE-1];

    always @(posedge clk) begin
        if (chip_en) begin
            if (wen)
                mem[w_addr] <= din;
            if (ren)
                dout <= mem[r_addr];
        end
    end

endmodule

module RF 
    #(parameter WIDTH = 4,
    parameter SIZE = 4,
    parameter ADDR_WIDTH = $clog2(SIZE))
    (input clk, 
    input ren, 
    input wen, 
    input [ADDR_WIDTH-1:0] r_addr, 
    input [ADDR_WIDTH-1:0] w_addr,
    input [WIDTH-1:0] din,
    output reg [WIDTH-1:0] dout);

    // instanciate memory
    reg [WIDTH-1 : 0] mem [0 : SIZE-1];

    always @(posedge clk) begin
        if (wen)
            mem[w_addr] <= din;

        if (ren)
            dout <= mem[r_addr];
    end
    
endmodule