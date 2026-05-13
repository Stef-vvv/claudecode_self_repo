// ============================================================================
// 模块名称: scan_chain (顶层配置扫描链)
// 在架构中的位置: SCAN CHAIN - 全局配置参数寄存器组
//
// 功能描述:
//   通过串行扫描链配置所有卷积加速器所需的维度/循环参数。
//   包含17个多比特参数寄存器，串联成一条总扫描链：
//
//   卷积层维度参数 (Layer Dimensions):
//     H (8bit):  输入特征图高度
//     W (8bit):  输入特征图宽度
//     R (4bit):  滤波器高度
//     S (4bit):  滤波器宽度
//     E (6bit):  输出通道数 (C_out通道维度)
//     F (6bit):  输入通道数 (C_in通道维度)
//
//   循环控制参数 (Loop Control):
//     C (10bit): 输入通道循环计数
//     M (10bit): 输出通道循环计数
//     N (3bit):  批处理循环计数
//     U (3bit):  步幅循环计数
//
//   PE阵列/调度参数 (PE Array/Scheduler):
//     m (8bit):  PE阵列内部行计数
//     n (3bit):  PE阵列内部列计数
//     e (6bit):  通道分片计数
//     p (5bit):  输出高度循环
//     q (3bit):  输出宽度子循环
//     r (2bit):  滤波器行子循环
//     t (3bit):  列方向子循环
//
//   扫描链串联顺序:
//   scan_in -> H -> W -> R -> S -> E -> F -> C -> M -> N -> U -> m -> n -> e -> p -> q -> r -> t -> scan_out
//
// 时钟域说明:
//   - negedge clk + posedge reset
//   - 所有参数在统一时钟域，与core_clk同步
// ============================================================================

module scan_chain #(
    // ==================== 卷积层维度参数位宽 ====================
    parameter H_WIDTH = 8,               // H: 输入特征图高度（默认8位，最大256）
    parameter W_WIDTH = 8,               // W: 输入特征图宽度（默认8位，最大256）
    parameter R_WIDTH = 4,               // R: 滤波器高度（默认4位，最大16，典型值3）
    parameter S_WIDTH = 4,               // S: 滤波器宽度（默认4位，最大16，典型值3）
    parameter E_WIDTH = 6,               // E: 输出通道数（默认6位，最大64）
    parameter F_WIDTH = 6,               // F: 输入通道数（默认6位，最大64）

    // ==================== 循环控制参数位宽 ====================
    parameter C_WIDTH = 10,              // C: 输入通道循环计数（默认10位，最大1024）
    parameter M_WIDTH = 10,              // M: 输出通道循环计数（默认10位，最大1024）
    parameter N_WIDTH = 3,               // N: 批处理循环计数（默认3位）
    parameter U_WIDTH = 3,               // U: 步幅循环计数（默认3位）

    // ==================== PE阵列/调度参数位宽 ====================
    parameter m_WIDTH = 8,               // m: PE阵列行计数（默认8位）
    parameter n_WIDTH = 3,               // n: PE阵列列计数（默认3位）
    parameter e_WIDTH = 6,               // e: 通道分片计数（默认6位）
    parameter p_WIDTH = 5,               // p: 输出高度循环（默认5位）
    parameter q_WIDTH = 3,               // q: 输出宽度子循环（默认3位）
    parameter r_WIDTH = 2,               // r: 滤波器行子循环（默认2位）
    parameter t_WIDTH = 3                // t: 列方向子循环（默认3位）
)(
    input  wire clk,                     // 时钟（negedge触发）
    input  wire reset,                   // 异步复位（高有效）
    input  wire scan_en,                 // 扫描使能（1=移位配置，0=正常输出配置值）
    input  wire scan_in,                 // 扫描链串行输入（配置数据入口）
    output wire scan_out,                // 扫描链串行输出（可级联更多链）

    // ==================== 卷积层维度参数输出 ====================
    output  logic  [H_WIDTH - 1:0] H,    // 输入特征图高度值
    output  logic  [W_WIDTH - 1:0] W,    // 输入特征图宽度值
    output  logic  [R_WIDTH - 1:0] R,    // 滤波器高度值
    output  logic  [S_WIDTH - 1:0] S,    // 滤波器宽度值
    output  logic  [E_WIDTH - 1:0] E,    // 输出通道数值
    output  logic  [F_WIDTH - 1:0] F,    // 输入通道数值

    // ==================== 循环控制参数输出 ====================
    output  logic  [C_WIDTH - 1:0] C,    // 输入通道循环计数值
    output  logic  [M_WIDTH - 1:0] M,    // 输出通道循环计数值
    output  logic  [N_WIDTH - 1:0] N,    // 批处理循环计数值
    output  logic  [U_WIDTH - 1:0] U,    // 步幅循环计数值

    // ==================== PE阵列/调度参数输出 ====================
    output  logic  [m_WIDTH - 1:0] m,    // PE阵列行计数值
    output  logic  [n_WIDTH - 1:0] n,    // PE阵列列计数值
    output  logic  [e_WIDTH - 1:0] e,    // 通道分片计数值
    output  logic  [p_WIDTH - 1:0] p,    // 输出高度循环值
    output  logic  [q_WIDTH - 1:0] q,    // 输出宽度子循环值
    output  logic  [r_WIDTH - 1:0] r,    // 滤波器行子循环值
    output  logic  [t_WIDTH - 1:0] t     // 列方向子循环值
);

    // ========================================================================
    // scan_w: 17个寄存器之间的扫描链互联线
    // scan_w[0] = H_reg.scan_out -> W_reg.scan_in
    // scan_w[1] = W_reg.scan_out -> R_reg.scan_in
    // ...
    // scan_w[15] = r_reg.scan_out -> t_reg.scan_in
    // scan_in -> H_reg, scan_out <- t_reg
    // ========================================================================
    logic [0:15] scan_w;

    // ========================================================================
    // 以下按串联顺序实例化17个参数寄存器
    // 每个寄存器的scan_out连接下一个寄存器的scan_in
    // ========================================================================

    // [参数1] H: 输入特征图高度 (8位)
    scan_ff_Nbit #(.DATA_WIDTH(H_WIDTH)) H_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_in),          // 扫描链入口
        .q(H),
        .scan_out(scan_w[0])        // -> W_reg
    );

    // [参数2] W: 输入特征图宽度 (8位)
    scan_ff_Nbit #(.DATA_WIDTH(W_WIDTH)) W_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[0]),        // <- H_reg
        .q(W),
        .scan_out(scan_w[1])        // -> R_reg
    );

   // [参数3] R: 滤波器高度 (4位)
   scan_ff_Nbit #(.DATA_WIDTH(R_WIDTH)) R_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[1]),
        .q(R),
        .scan_out(scan_w[2])        // -> S_reg
    );

   // [参数4] S: 滤波器宽度 (4位)
   scan_ff_Nbit #(.DATA_WIDTH(S_WIDTH)) S_reg (
         .clk(clk),
         .reset(reset),
         .scan_en(scan_en),
         .scan_in(scan_w[2]),
         .q(S),
         .scan_out(scan_w[3])       // -> E_reg
    );

    // [参数5] E: 输出通道数 (6位)
    scan_ff_Nbit #(.DATA_WIDTH(E_WIDTH)) E_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[3]),
        .q(E),
        .scan_out(scan_w[4])        // -> F_reg
    );

    // [参数6] F: 输入通道数 (6位)
    scan_ff_Nbit #(.DATA_WIDTH(F_WIDTH)) F_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[4]),
        .q(F),
        .scan_out(scan_w[5])        // -> C_reg
    );

    // [参数7] C: 输入通道循环计数 (10位)
    scan_ff_Nbit #(.DATA_WIDTH(C_WIDTH)) C_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[5]),
        .q(C),
        .scan_out(scan_w[6])        // -> M_reg
    );

    // [参数8] M: 输出通道循环计数 (10位)
    scan_ff_Nbit #(.DATA_WIDTH(M_WIDTH)) M_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[6]),
        .q(M),
        .scan_out(scan_w[7])        // -> N_reg
    );

    // [参数9] N: 批处理循环计数 (3位)
    scan_ff_Nbit #(.DATA_WIDTH(N_WIDTH)) N_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[7]),
        .q(N),
        .scan_out(scan_w[8])        // -> U_reg
    );

    // [参数10] U: 步幅循环计数 (3位)
    scan_ff_Nbit #(.DATA_WIDTH(U_WIDTH)) U_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[8]),
        .q(U),
        .scan_out(scan_w[9])        // -> m_reg
    );

    // [参数11] m: PE阵列行计数 (8位)
    scan_ff_Nbit #(.DATA_WIDTH(m_WIDTH)) m_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[9]),
        .q(m),
        .scan_out(scan_w[10])       // -> n_reg
    );

    // [参数12] n: PE阵列列计数 (3位)
    scan_ff_Nbit #(.DATA_WIDTH(n_WIDTH)) n_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[10]),
        .q(n),
        .scan_out(scan_w[11])       // -> e_reg
    );

    // [参数13] e: 通道分片计数 (6位)
    scan_ff_Nbit #(.DATA_WIDTH(e_WIDTH)) e_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[11]),
        .q(e),
        .scan_out(scan_w[12])       // -> p_reg
    );

    // [参数14] p: 输出高度循环 (5位)
    scan_ff_Nbit #(.DATA_WIDTH(p_WIDTH)) p_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[12]),
        .q(p),
        .scan_out(scan_w[13])       // -> q_reg
    );

    // [参数15] q: 输出宽度子循环 (3位)
    scan_ff_Nbit #(.DATA_WIDTH(q_WIDTH)) q_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[13]),
        .q(q),
        .scan_out(scan_w[14])       // -> r_reg
    );

    // [参数16] r: 滤波器行子循环 (2位)
    scan_ff_Nbit #(.DATA_WIDTH(r_WIDTH)) r_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[14]),
        .q(r),
        .scan_out(scan_w[15])       // -> t_reg
    );

    // [参数17] t: 列方向子循环 (3位) — 扫描链最后一个寄存器
    scan_ff_Nbit #(.DATA_WIDTH(t_WIDTH)) t_reg (
        .clk(clk),
        .reset(reset),
        .scan_en(scan_en),
        .scan_in(scan_w[15]),
        .q(t),
        .scan_out(scan_out)         // 扫描链出口
    );

endmodule
