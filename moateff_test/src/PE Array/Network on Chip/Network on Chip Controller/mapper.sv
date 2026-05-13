module mapper #(
    parameter DIM4_WIDTH = 8,  
    parameter DIM3_WIDTH = 8, 
    parameter DIM2_WIDTH = 8,  
    parameter DIM1_WIDTH = 8,
    
    parameter IDX4_WIDTH = 8,  
    parameter IDX3_WIDTH = 8, 
    parameter IDX2_WIDTH = 8,  
    parameter IDX1_WIDTH = 8,
        
    parameter ROW_MAJOR = 1,   // 1 = Row-major, 0 = Column-major
    parameter ADDR_WIDTH = 32 
)( 
    input  logic [DIM4_WIDTH - 1:0] dim4, 
    input  logic [DIM3_WIDTH - 1:0] dim3, 
    input  logic [DIM2_WIDTH - 1:0] dim2,
    input  logic [DIM1_WIDTH - 1:0] dim1,
    
    input  logic [IDX4_WIDTH - 1:0] idx4,
    input  logic [IDX3_WIDTH - 1:0] idx3, 
    input  logic [IDX2_WIDTH - 1:0] idx2,
    input  logic [IDX1_WIDTH - 1:0] idx1,
    
    // input  logic [ADDR_WIDTH - 1:0] base_addr,
    output logic [ADDR_WIDTH - 1:0] addr
);

    // Compute the address based on row-major or column-major order, with base address input
    generate
        if (ROW_MAJOR) begin : row_major_block
            always @(*) begin
                addr = (idx4 * (dim3 * dim2 * dim1)) +
                       (idx3 * (dim2 * dim1)) +
                       (idx2 * dim1) +
                        idx1;
            end
        end else begin : column_major_block
            always @(*) begin
                addr = (idx4 * (dim3 * dim2 * dim1)) +
                       (idx3 * (dim2 * dim1)) +
                       (idx1 * dim2) +
                        idx2;
            end
        end
    endgenerate

endmodule
