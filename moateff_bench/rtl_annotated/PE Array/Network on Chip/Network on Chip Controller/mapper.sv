// =============================================================================
// 模块名称: mapper (地址映射器)
// 功能描述: 将4维索引(idx4, idx3, idx2, idx1)映射为线性存储器地址(addr)。
//           支持行主序(Row-major)和列主序(Column-major)两种映射方式。
// 数据流角色: 地址生成核心 —— 位于索引生成器和全局缓冲区读端口之间,
//           将迭代逻辑生成的多维坐标转换为RAM的一维地址。
// 地址计算公式:
//   行主序(ROW_MAJOR=1): addr = idx4 * dim3*dim2*dim1 + idx3 * dim2*dim1 + idx2 * dim1 + idx1
//   列主序(ROW_MAJOR=0): addr = idx4 * dim3*dim2*dim1 + idx3 * dim2*dim1 + idx1 * dim2 + idx2
// 4维数组布局: [dim4][dim3][dim2][dim1]
//   - dim4: 最外层 (e.g., 输出通道组数/批大小)
//   - dim3: 次外层 (e.g., 输入通道组数/输出通道数)
//   - dim2: 次内层 (e.g., 行数/高度)
//   - dim1: 最内层 (e.g., 列数/宽度)
// =============================================================================

module mapper #(
    // 各维度大小位宽
    parameter DIM4_WIDTH = 8,
    parameter DIM3_WIDTH = 8,
    parameter DIM2_WIDTH = 8,
    parameter DIM1_WIDTH = 8,

    // 各维度索引位宽
    parameter IDX4_WIDTH = 8,
    parameter IDX3_WIDTH = 8,
    parameter IDX2_WIDTH = 8,
    parameter IDX1_WIDTH = 8,

    // 存储顺序: 1 = 行主序 (Row-major), 0 = 列主序 (Column-major)
    // 行主序: dim1变化最快, dim4变化最慢
    // 列主序: dim2变化最快, dim4变化最慢
    parameter ROW_MAJOR = 1,
    // 线性地址位宽
    parameter ADDR_WIDTH = 32
)(
    // 各维度尺寸输入
    input  logic [DIM4_WIDTH - 1:0] dim4,
    input  logic [DIM3_WIDTH - 1:0] dim3,
    input  logic [DIM2_WIDTH - 1:0] dim2,
    input  logic [DIM1_WIDTH - 1:0] dim1,

    // 各维度索引输入
    input  logic [IDX4_WIDTH - 1:0] idx4,   // 最外层索引
    input  logic [IDX3_WIDTH - 1:0] idx3,   // 次外层索引
    input  logic [IDX2_WIDTH - 1:0] idx2,   // 次内层索引
    input  logic [IDX1_WIDTH - 1:0] idx1,   // 最内层索引

    // 线性地址输出
    output logic [ADDR_WIDTH - 1:0] addr
);

    // 根据ROW_MAJOR参数选择地址计算方式
    generate
        if (ROW_MAJOR) begin : row_major_block
            // ---- 行主序映射 ----
            // addr = idx4*(dim3*dim2*dim1) + idx3*(dim2*dim1) + idx2*(dim1) + idx1
            // 步长: dim3*dim2*dim1 (跨dim4), dim2*dim1 (跨dim3), dim1 (跨dim2), 1 (跨dim1)
            always @(*) begin
                addr = (idx4 * (dim3 * dim2 * dim1)) +
                       (idx3 * (dim2 * dim1)) +
                       (idx2 * dim1) +
                        idx1;
            end
        end else begin : column_major_block
            // ---- 列主序映射 ----
            // addr = idx4*(dim3*dim2*dim1) + idx3*(dim2*dim1) + idx1*(dim2) + idx2
            // 与行主序的区别: dim2和dim1交换, idx2和idx1交换
            always @(*) begin
                addr = (idx4 * (dim3 * dim2 * dim1)) +
                       (idx3 * (dim2 * dim1)) +
                       (idx1 * dim2) +
                        idx2;
            end
        end
    endgenerate

endmodule
