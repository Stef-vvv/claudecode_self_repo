# Q5: Scan Chain — How Configuration Works

## 1. Scan Chain Hierarchy

The Eyeriss RTL has a **two-level scan chain**:

### Level 1: Top-Level Parameters (`scan_chain.sv`)

Located in `H:/moateff_test/src/SCAN CHAIN/scan_chain.sv`. Configures 16 mapping/shape parameters.

### Level 2: PE Array Configuration (inside `pe_array.sv`)

Configures per-PE enables, local network selectors, GIN tag IDs (ifmap/filter/ipsum), and GON tag IDs (opsum). This uses separate scan chains embedded within the `pe_array` module.

The two levels are daisy-chained: `scan_w` from Level 1 feeds Level 2.

## 2. Scan Flip-Flop Primitives

### `scan_ff.sv` — Single-bit scan flip-flop

```verilog
module scan_ff (
    input clk, reset, scan_en, scan_in,
    output q, scan_out
);
    reg q_internal;
    always @(negedge clk or posedge reset) begin
        if (reset)       q_internal <= 1'b0;
        else if (scan_en) q_internal <= scan_in;
    end
    assign q = (~scan_en) & q_internal;
    assign scan_out = q_internal;
endmodule
```

Key behavior:
- When `scan_en = 1`: shifts data through (`scan_in -> q_internal -> scan_out`), output `q = 0` (masked)
- When `scan_en = 0`: holds value, output `q = q_internal` (visible to logic)
- Operates on **negedge clk** with **posedge reset**

### `scan_ff_Nbit.sv` — Multi-bit scan register

Chains N `scan_ff` instances in series (`generate for` loop). The most significant bit is closest to `scan_in`, the least significant bit drives `scan_out`. This means bits are shifted in **MSB-first** order.

```verilog
for (i = DATA_WIDTH - 1; i >= 0; i = i - 1) begin : SCAN_FF
    scan_ff scan_ff_inst (.scan_in(scan_w[i+1]), .q(q[i]), .scan_out(scan_w[i]));
end
```

## 3. Scan Chain Register Order (Top-Level `scan_chain.sv`)

The scan chain connects 16 registers in series. The order (from `scan_in` to `scan_out`) is:

| Position | Register | Width | Bits | Description |
|----------|----------|-------|------|-------------|
| 0 (first) | H_reg | 8 | [7:0] | Ifmap height |
| 1 | W_reg | 8 | [15:8] | Ifmap width |
| 2 | R_reg | 4 | [19:16] | Filter height |
| 3 | S_reg | 4 | [23:20] | Filter width |
| 4 | E_reg | 6 | [29:24] | Ofmap height |
| 5 | F_reg | 6 | [35:30] | Ofmap width |
| 6 | C_reg | 10 | [45:36] | Ifmap channels |
| 7 | M_reg | 10 | [55:46] | Ofmap channels |
| 8 | N_reg | 3 | [58:56] | Ifmap tiling: rows per pass |
| 9 | U_reg | 3 | [61:59] | Stride |
| 10 | m_reg | 8 | [69:62] | Ofmap tiling: filters per pass |
| 11 | n_reg | 3 | [72:70] | Ifmap tiling: channels per pass |
| 12 | e_reg | 6 | [78:73] | Ofmap tiling: rows per tile |
| 13 | p_reg | 5 | [83:79] | Filters per PE |
| 14 | q_reg | 3 | [86:84] | Ifmap channels per PE group |
| 15 | r_reg | 2 | [88:87] | Filter rows per PE group |
| 16 (last) | t_reg | 3 | [91:89] | Filter channel groups per PE |

**Total parameter bits: 92 bits** (8+8+4+4+6+6+10+10+3+3+8+3+6+5+3+2+3)

## 4. Level 2: PE Array Scan Chain (inside `pe_array.sv`, lines 120-334)

After the 92 parameter bits, additional scan chains configure the 12x14 PE array. The scan chain continues through (in order):

### Block A: PE Enables (12 x 14 = 168 bits)
```
for each row i (0 to 11):
    scan_ff_Nbit #(14) pe_array_enable_ff  // 14 bits per row
```
Each bit `enable[i][j]` controls whether PE(i,j) is clock-gated. `0` = disabled (clock gated off, saves power), `1` = enabled.

### Block B: Ipsum Local Network Selectors (12 x 14 = 168 bits)
```
for each row i (0 to 11):
    scan_ff_Nbit #(14) ipsum_ln_ff
```
Each bit `ipsum_ln_sel[i][j]` selects the psum data source for PE(i,j):
- `0`: psum comes from PE below (PE(i+1, j)) — row-stationary accumulation
- `1`: psum comes from GIN (external partial sum from GLB)

### Block C: Opsum Local Network Selectors (12 x 14 = 168 bits)
```
for each row i (0 to 11):
    scan_ff_Nbit #(14) opsum_ln_ff
```
Each bit `opsum_ln_sel[i][j]` selects the opsum destination for PE(i,j):
- `0`: opsum goes to PE above (PE(i-1, j)) — row-stationary forwarding
- `1`: opsum goes to GON (to GLB/external)

### Block D: Ifmap GIN Tag IDs (scanned into `ifmap_gin_inst`)
The GIN has its own internal scan chain for tag IDs. The ifmap GIN's MCC instances (one per row, one per column per row) each have a `scan_ff_Nbit` for their row/column tag ID. This configures which ifmap row/col tag each PE receives data for.

### Block E: Filter GIN Tag IDs (scanned into `filter_gin_inst`)
Same structure as ifmap, but with filter tag widths (ROW_TAG=4, COL_TAG=4).

### Block F: Ipsum GIN Tag IDs (scanned into `ipsum_gin_inst`)
Same structure, with psum tag widths.

### Block G: Opsum GON Tag IDs (scanned into `opsum_gon_inst`)
GON also has internal scan chains for output tag IDs.

## 5. Total Scan Chain Bit Count

| Section | Bits per unit | Units | Total bits |
|---------|---------------|-------|------------|
| Parameters (H..t) | 92 | 1 | **92** |
| PE Enables | 14 | 12 rows | **168** |
| Ipsum LN Selectors | 14 | 12 rows | **168** |
| Opsum LN Selectors | 14 | 12 rows | **168** |
| Ifmap GIN IDs: row_id(4) + 14 cols(5) | 74 | 12 rows | **888** |
| Filter GIN IDs: 15 x 4-bit | 60 | 12 rows | **720** |
| Ipsum GIN IDs: 15 x 4-bit | 60 | 12 rows | **720** |
| Opsum GON IDs: 15 x 4-bit | 60 | 12 rows | **720** |
| **GRAND TOTAL** | | | **3,644 bits** |

## 6. How `serial_data.txt` Becomes Register Values

### Step 1: `config_script.py` Generates Bits

The Python script (`config/config_script.py`):
1. Reads config text files from each layer folder (conv1-conv5)
2. Parses parameters, enables, LN selectors, and IDs into binary strings
3. Concatenates in order: `parameters + enables + ipsum_ln_selectors + opsum_ln_selectors + ifmap_ids + filters_ids + ipsum_ids + opsum_ids`
4. Reverses the concatenated string and writes to `serial_data.txt` (one bit per line, plus a dummy first line)

```python
full_chain = parameters + enables + ipsum_ln_selectors + opsum_ln_selectors + ifmap_ids + filters_ids + ipsum_ids + opsum_ids

# Write serial_data.txt (REVERSED for LSB-first shift)
reversed_chain = list(reversed(full_chain))
f.write(f'{reversed_chain[0]}\n')  # dummy first line
for bit in reversed_chain:
    f.write(f'{bit}\n')
```

The reversal is necessary because the scan chain shifts bits through sequentially: the first bit shifted in ends up in the **last** register (position 16, `t_reg`), while the last bit shifted ends up in the **first** register (`H_reg`). By reversing, the config generator ensures bits land in the correct registers.

Actually, re-tracing: in the scan chain, `scan_in` -> H_reg(MSB first) -> ... -> t_reg -> `scan_out`. If we shift bits b0, b1, b2, ... bn into `scan_in`:
- After n+1 cycles, b0 is in t_reg[0] (last bit of last register)
- bn is in H_reg[7] (first bit of first register)

So the config string needs to be: [H bits][W bits]...[t bits], and the first bit shifted into `scan_in` becomes the MSB of the LAST register. This means when writing the serial_data.txt, bits should be in reverse order of the config string, so the first serial bit corresponds to t[0], next to t[1], etc.

### Step 2: `cfg_pkg.sv` Clocks Bits In

The SystemVerilog package `cfg_pkg.sv`:
```systemverilog
task cfg_scan_chain(input string filename);
    // Open file
    shared_pkg::scan_en = 1;        // Enable scan mode
    while (!$feof(file)) begin
        // Read one bit per line
        $sscanf(line, "%d", bit_val);
        shared_pkg::scan_in = bit_val;
        wait_core_cycle(1);         // One clock per bit
    end
    shared_pkg::scan_en = 0;        // Disable scan, latch values
endtask
```

### Step 3: Testbench Calls Config

In the testbench (`Eyeriss_tb.sv` or layer-specific TB):
```systemverilog
cfg_pkg::conv1_cfg();  // Configures for AlexNet Conv1
// This asserts scan_en, shifts 3644 bits, then deasserts scan_en
```

## 7. Config File Formats

### `parameters.txt`
```
H = 8
W = 8
R = 3
S = 3
...
t = 1
```
Parsed by `parse_parameters()`: each value is formatted as binary with its parameter width, concatenated in order.

### `enables.txt` (12 rows x 14 cols)
```
1 0 0 0 0 0 0 0 0 0 0 0 0 0
1 0 0 0 0 0 0 0 0 0 0 0 0 0
1 0 0 0 0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0 0 0 0 0
...
```
1 = PE enabled, 0 = PE disabled. For tiny test: only first 3 rows, column 0 are enabled.

### `ipsum_ln_selectors.txt` / `opsum_ln_selectors.txt` (12x14)
Same format as enables. 0 = use row-stationary path (PE-to-PE), 1 = use GLB/GIN/GON path.

### `ifmap_ids.txt` (12 rows, 15 values each)
```
0  0 31 31 31 31 31 31 31 31 31 31 31 31 31
1  0 31 31 31 31 ...
...
```
First value per row: 4-bit row ID. Remaining 14 values: 5-bit column IDs. Values 15 and 31 represent "no tag match" (disabled).

### `filters_ids.txt` / `ipsum_ids.txt` / `opsum_ids.txt` (12x15)
All 15 values per row are 4-bit IDs. Values of 15 = disabled.

## 8. What Each Config File Controls (Tiny Test Example)

For the tiny test layer (`config/tiny/`):

| File | Purpose |
|------|---------|
| `parameters.txt` | H=8,W=8,R=3,S=3,E=6,F=6,C=1,M=1,N=1,U=1,m=1,n=1,e=6,p=1,q=1,r=1,t=1 |
| `enables.txt` | Only PE(0,0), PE(1,0), PE(2,0) enabled; rest disabled |
| `ipsum_ln_selectors.txt` | Controls whether psum comes from PE below (row-stationary) or GLB |
| `opsum_ln_selectors.txt` | Controls whether opsum goes to PE above or to GON/GLB |
| `ifmap_ids.txt` | Row IDs 0,1,2 for rows 0,1,2; col IDs 0 for col 0; rest=31 (disabled) |
| `filters_ids.txt` | Filter tag IDs per PE (row 0->15, row 1->15, row 2->15 for col 0; rest=15 disabled) |
| `ipsum_ids.txt` | Ipsum tag IDs per PE |
| `opsum_ids.txt` | Opsum tag IDs per PE |
| `serial_data.txt` | All of the above, combined into one bitstream (reversed, one bit per line) |

## 9. How PEs Are Enabled/Disabled

Each PE has a `clk_gating` module controlled by `enable[i][j]`:
```verilog
// In pe_wrapper.v
clk_gating clk_gating_inst (
    .enable(enable),
    .clk(clk),
    .gated_clk(gated_clk)
);
```
When `enable=0`, the PE's clock is gated off, saving dynamic power. The PE's internal state is frozen. The `busy` signal from a disabled PE is ignored.

## 10. How NoC IDs Are Assigned

Each GIN MCC (`gin_mcc.sv`) has a scan-programmable tag ID register:
```verilog
scan_ff_Nbit #(.DATA_WIDTH(TAG_WIDTH)) scan_ff_Nbit_inst (
    .scan_in(scan_in_id),
    .q(q_id),                    // This PE's row/column tag
    .scan_out(scan_out_id)
);

assign equal_tag = (q_id == tag);
assign data_out = enable_mid ? data_in : {DATA_WIDTH{1'b0}};
```

The tag comparator matches the incoming data's row/col tag against the scan-programmed ID. Only PEs with matching tags receive the data. This is how the NoC routes data to specific PEs — by programming each PE's tag ID through the scan chain.

For the tiny test, only PEs (0,0), (1,0), (2,0) have valid ifmap IDs programmed; all others have ID=31 or 15 (out of range = never matches).















































你这个问题正好把前面对 NoC 架构的讨论推到了最核心的物理实现层。让我们直接切开 GIN 和 GON 的 Verilog 代码，看清 "reconfigurable IDs" 和 "tag matching" 是如何在每个 PE 里用硅片上的晶体管实现的。

### 1. "Reconfigurable IDs" 的物理形态：一个串行移位寄存器链

在 `gin_mcc.sv`（GIN 多播控制器）里，我们并没有发现一个硬编码的 ID。相反，我们看到了一行关键的实例化代码：

```verilog
// gin_mcc.sv
scan_ff_Nbit #(.DATA_WIDTH(TAG_WIDTH)) scan_ff_Nbit_inst (
    .clk(clk),
    .reset(reset),
    .scan_en(scan_en_id),
    .scan_in(scan_in_id),
    .q(q_id),               // 这就是每个 X 总线或 PE 的 "Reconfigurable ID"
    .scan_out(scan_out_id)
);
```

这个 `scan_ff_Nbit` 是一个串行移位寄存器。**它，就是可重配置 ID 的物理实现。**

它的工作流程如下：
1.  **串行灌入**：在每一层计算开始前（或者芯片初始化时），顶层控制器会拉高 `scan_en` 信号。然后，一个很长的配置比特流（你之前问过的 1794 位扫描链就是它的一部分）从 `scan_in` 端口一位一位地被灌入。
2.  **并行锁存**：当灌入停止，`scan_en` 拉低，此时移位寄存器里锁存的那几位（这里是 `TAG_WIDTH` 位，比如 4 位或 5 位）就是这个 PE 或这条 X 总线在本层的唯一身份标识。
3.  **即插即用**：这个身份标识 `q_id` 被直接输出，用于后续的比较。当下一层需要新的 ID 时，新的比特流会再次被灌入，旧 ID 被冲掉。这就实现了“**在运行时重配置**”。

### 2. "Tag Matching" 的组合逻辑：一个简单的数字比较器

McConnell 芯片搞定身份标识后，我们就有了 `q_id`。匹配过程非常简单，就在同一模块的这几行组合逻辑里完成：

```verilog
// gin_mcc.sv
assign equal_tag = (q_id == tag);
assign enable_mid = enable_in & ready_in & equal_tag;
assign enable_out = enable_mid;
assign data_out = enable_mid ? data_in : {DATA_WIDTH{1'b0}};
```

这本质上就是一个 **1 比特的数字比较器**。
1.  **接收数据包**：每个周期，一个数据包从上一级传来。这个数据包不仅仅是数据本身 (`data_in`)，还贴着两个标签：`row_tag` 和 `col_tag`。
2.  **比较行标签**：数据首先到达 **Y 总线** 上的一个 `gin_mcc`。它会把 `row_tag` 和自己的 `q_id` 比较。
3.  **比较列标签**：如果行匹配，数据就传到 **X 总线**。X 总线再把 `col_tag` 和自己那条线上的多个 MCC 的 `q_id` 比较。
4.  **精确投递**：只有当行和列都匹配的那个 PE，它的 `equal_tag` 才为 `1`，`enable_mid` 才有效。此时，`data_out` 才等于 `data_in`；其他所有 PE 的 `data_out` 都是全零，并且后续操作被时钟门控，以节省能量。

### 3. 行与列 ID 的分发策略：如何在 12x14 网格上多播？

现在我们理解了 ID 和匹配的机制，再来回答“怎么分配”。这部分逻辑不在 GIN 自身，而在于生成标签的控制器（如 `filter_tag_generator.sv` 等）。分配策略完全取决于这一层的**数据流映射需求**。

以滤波器 GIN 为例（`ROW_TAG_WIDTH=4`, `COL_TAG_WIDTH=4`）：
- **水平广播（同一行，不同列）**：需要将相同的滤波器发送给同一行的多个 PE。分配器会生成一个 `row_tag`（比如 `0011`，代表第 4 行），和一个 `col_tag`。为了让这一整行 PE 都接收，分配器会给这一行所有 PE 的 X 总线和 PE MCC 都配置**相同的列 ID**（比如 `0000`）。这样，当 `col_tag=0000` 时，这整行的所有 PE 都会 `equal_tag=1`，从而一次性完成广播。
- **单播（指定 PE）**：计算器则为每个 PE 及其 X 总线分配一个**唯一的组合**，比如 PE(1,2) 的 ID 是 `row=0001, col=0010`。分配器只生成这组特定的标签，实现单播。
- **对角线传递（Ifmap 的特殊 5 位需求）**：Ifmap GIN 的 `COL_TAG_WIDTH=5`，是为了支持更多列。在“对角线滑动”这种模式下，同一列的不同 PE 会在不同周期接收数据。分配器需要给**每一列**的 PE 都配送一个独一无二的列 ID（5 位可以支持最多 32 种不同的列），表示它们在滑动窗口时间轴上的位置。

所有 PE 的 ID 都是在每层开始前，通过扫描链串行配置好的。然后，顶层控制器在每个周期根据数据处理趟的进度，动态生成数据附带的 `(row, col)` 标签。这套“**静态配置 ID + 动态生成标签**”的机制，共同构成了 Eyeriss NoC 多播的核心，让它在不改变硬件连接的情况下，支持各种灵活的数据流动模式。















































**第五季度问题：扫描链 — 配置如何工作**

**1. 扫描链层次结构**

Eyeriss RTL 具有 **两级扫描链**：

**第一级：顶层参数（`scan_chain.sv`）**

位于 `H:/moateff_test/src/SCAN CHAIN/scan_chain.sv`。配置16个映射/形状参数。

**第二级：PE阵列配置（在 `pe_array.sv` 内部）**

配置每个PE的使能、局部网络选择器、GIN标签ID（ifmap/filter/ipsum）和GON标签ID（opsum）。这使用嵌入在 `pe_array` 模块中的独立扫描链。

两级被菊花链串联：来自第一级的 `scan_w` 馈送给第二级。

**2. 扫描触发器原语**

**`scan_ff.sv` — 单位扫描触发器**

```verilog
module scan_ff (
    input clk, reset, scan_en, scan_in,
    output q, scan_out
);
    reg q_internal;
    always @(negedge clk or posedge reset) begin
        if (reset)       q_internal <= 1'b0;
        else if (scan_en) q_internal <= scan_in;
    end
    assign q = (~scan_en) & q_internal;
    assign scan_out = q_internal;
endmodule
```

关键行为：
-   当 `scan_en = 1` 时：移位数据通过（`scan_in -> q_internal -> scan_out`），输出 `q = 0`（被屏蔽）
-   当 `scan_en = 0` 时：保持值，输出 `q = q_internal`（对逻辑可见）
-   在 **negedge clk** 上操作，带有 **posedge reset**

**`scan_ff_Nbit.sv` — 多比特扫描寄存器**

将 N 个 `scan_ff` 实例用 `generate for` 循环串联。最高有效位最靠近 `scan_in`，最低有效位驱动 `scan_out`。这意味着比特以 **MSB优先** 的顺序被移入。

```verilog
for (i = DATA_WIDTH - 1; i >= 0; i = i - 1) begin : SCAN_FF
    scan_ff scan_ff_inst (.scan_in(scan_w[i+1]), .q(q[i]), .scan_out(scan_w[i]));
end
```

**3. 扫描链寄存器顺序（顶层 `scan_chain.sv`）**

扫描链将16个寄存器串联。顺序（从 `scan_in` 到 `scan_out`）如下：

| 位置 | 寄存器 | 宽度 | 比特位 | 描述 |
|---|---|---|---|---|
| 0（第一个） | H_reg | 8 | [7:0] | Ifmap 高度 |
| 1 | W_reg | 8 | [15:8] | Ifmap 宽度 |
| 2 | R_reg | 4 | [19:16] | 滤波器高度 |
| 3 | S_reg | 4 | [23:20] | 滤波器宽度 |
| 4 | E_reg | 6 | [29:24] | Ofmap 高度 |
| 5 | F_reg | 6 | [35:30] | Ofmap 宽度 |
| 6 | C_reg | 10 | [45:36] | Ifmap 通道数 |
| 7 | M_reg | 10 | [55:46] | Ofmap 通道数 |
| 8 | N_reg | 3 | [58:56] | Ifmap 分块：每趟行数 |
| 9 | U_reg | 3 | [61:59] | 步长 |
| 10 | m_reg | 8 | [69:62] | Ofmap 分块：每趟滤波器数 |
| 11 | n_reg | 3 | [72:70] | Ifmap 分块：每趟通道数 |
| 12 | e_reg | 6 | [78:73] | Ofmap 分块：每块行数 |
| 13 | p_reg | 5 | [83:79] | 每个PE的滤波器数 |
| 14 | q_reg | 3 | [86:84] | 每个PE组的Ifmap通道数 |
| 15 | r_reg | 2 | [88:87] | 每个PE组的滤波器行数 |
| 16（最后一个） | t_reg | 3 | [91:89] | 每个PE的滤波器通道组数 |

**总参数比特数：92比特** (8+8+4+4+6+6+10+10+3+3+8+3+6+5+3+2+3)

**4. 第二级：PE阵列扫描链（在 `pe_array.sv` 内部，第120-334行）**

在92个参数比特之后，额外的扫描链配置12x14 PE阵列。扫描链按以下顺序继续（依次为）：

**模块 A：PE 使能（12 x 14 = 168 比特）**
```
for 每一行 i（0 到 11）：
    scan_ff_Nbit #(14) pe_array_enable_ff  // 每行14比特
```
每个比特 `enable[i][j]` 控制 PE(i,j) 是否被时钟门控。`0` = 禁用（时钟门控关闭，节省功耗），`1` = 启用。

**模块 B：Ipsum 局部网络选择器（12 x 14 = 168 比特）**
```
for 每一行 i（0 到 11）：
    scan_ff_Nbit #(14) ipsum_ln_ff
```
每个比特 `ipsum_ln_sel[i][j]` 为 PE(i,j) 选择 psum 数据源：
-   `0`：psum 来自下方 PE（PE(i+1, j)）—— 行平稳累积
-   `1`：psum 来自 GIN（来自 GLB 的外部部分和）

**模块 C：Opsum 局部网络选择器（12 x 14 = 168 比特）**
```
for 每一行 i（0 到 11）：
    scan_ff_Nbit #(14) opsum_ln_ff
```
每个比特 `opsum_ln_sel[i][j]` 为 PE(i,j) 选择 opsum 目的地：
-   `0`：opsum 去向上方 PE（PE(i-1, j)）—— 行平稳转发
-   `1`：opsum 去向 GON（到 GLB/外部）

**模块 D：Ifmap GIN 标签 ID（扫描进 `ifmap_gin_inst`）**
GIN 拥有自己的内部扫描链用于标签 ID。ifmap GIN 的 MCC 实例（每行一个，每行每列一个）各自拥有一个 `scan_ff_Nbit` 用于其行/列标签 ID。这配置了每个 PE 接收哪个 ifmap 行/列标签的数据。

**模块 E：滤波器 GIN 标签 ID（扫描进 `filter_gin_inst`）**
与 ifmap 结构相同，但使用滤波器标签宽度（ROW_TAG=4, COL_TAG=4）。

**模块 F：Ipsum GIN 标签 ID（扫描进 `ipsum_gin_inst`）**
结构相同，使用 psum 标签宽度。

**模块 G：Opsum GON 标签 ID（扫描进 `opsum_gon_inst`）**
GON 也拥有用于输出标签 ID 的内部扫描链。

**5. 扫描链总比特数**

| 部分 | 每单元比特数 | 单元数 | 总比特数 |
|---|---|---|---|
| 参数（H..t） | 92 | 1 | **92** |
| PE 使能 | 14 | 12 行 | **168** |
| Ipsum LN 选择器 | 14 | 12 行 | **168** |
| Opsum LN 选择器 | 14 | 12 行 | **168** |
| Ifmap GIN ID：row_id(4) + 14 cols(5) | 74 | 12 行 | **888** |
| 滤波器 GIN ID：15 x 4-bit | 60 | 12 行 | **720** |
| Ipsum GIN ID：15 x 4-bit | 60 | 12 行 | **720** |
| Opsum GON ID：15 x 4-bit | 60 | 12 行 | **720** |
| **总计** | | | **3,644 比特** |

**6. `serial_data.txt` 如何变成寄存器值**

**步骤 1：`config_script.py` 生成比特**

Python 脚本（`config/config_script.py`）：
1.  从每个层文件夹（conv1-conv5）读取配置文本文件
2.  将参数、使能、LN 选择器和 ID 解析为二进制字符串
3.  按顺序拼接：`parameters + enables + ipsum_ln_selectors + opsum_ln_selectors + ifmap_ids + filters_ids + ipsum_ids + opsum_ids`
4.  反转拼接后的字符串，并写入 `serial_data.txt`（每行一个比特，外加一个哑元第一行）

```python
full_chain = parameters + enables + ipsum_ln_selectors + opsum_ln_selectors + ifmap_ids + filters_ids + ipsum_ids + opsum_ids

# 写入 serial_data.txt（反转，用于 LSB优先 移位）
reversed_chain = list(reversed(full_chain))
f.write(f'{reversed_chain[0]}\n')  # 哑元第一行
for bit in reversed_chain:
    f.write(f'{bit}\n')
```

反转是必要的，因为扫描链按顺序移入比特：第一个移入的比特最终进入 **最后一个** 寄存器（位置16，`t_reg`），而最后一个移入的比特最终进入 **第一个** 寄存器（`H_reg`）。通过反转，配置生成器确保比特落入正确的寄存器。

实际上，重新追踪：在扫描链中，`scan_in` -> H_reg (MSB 优先) -> ... -> t_reg -> `scan_out`。如果我们将比特 b0, b1, b2, ... bn 移入 `scan_in`：
-   在 n+1 个周期后，b0 在 t_reg[0] 中（最后一个寄存器的最后一位）
-   bn 在 H_reg[7] 中（第一个寄存器的第一位）

所以配置字符串需要是：[H bits][W bits]...[t bits]，并且移入 `scan_in` 的第一个比特成为最后一个寄存器的 MSB。这意味着当写入 serial_data.txt 时，比特应该按配置字符串的反序，这样第一个串行比特对应 t[0]，下一个对应 t[1]，依此类推。

**步骤 2：`cfg_pkg.sv` 将比特时钟送入**

SystemVerilog 包 `cfg_pkg.sv`：
```systemverilog
task cfg_scan_chain(input string filename);
    // 打开文件
    shared_pkg::scan_en = 1;        // 使能扫描模式
    while (!$feof(file)) begin
        // 每行读取一个比特
        $sscanf(line, "%d", bit_val);
        shared_pkg::scan_in = bit_val;
        wait_core_cycle(1);         // 每个比特一个时钟周期
    end
    shared_pkg::scan_en = 0;        // 禁用扫描，锁存值
endtask
```

**步骤 3：测试台调用配置**

在测试台（`Eyeriss_tb.sv` 或特定于层的测试台）中：
```systemverilog
cfg_pkg::conv1_cfg();  // 为 AlexNet Conv1 进行配置
// 这断言 scan_en，移入 3644 个比特，然后撤销断言 scan_en
```

**7. 配置文件格式**

**`parameters.txt`**
```
H = 8
W = 8
R = 3
S = 3
...
t = 1
```
由 `parse_parameters()` 解析：每个值以其参数宽度被格式化为二进制，并按顺序拼接。

**`enables.txt`（12 行 x 14 列）**
```
1 0 0 0 0 0 0 0 0 0 0 0 0 0
1 0 0 0 0 0 0 0 0 0 0 0 0 0
1 0 0 0 0 0 0 0 0 0 0 0 0 0
0 0 0 0 0 0 0 0 0 0 0 0 0 0
...
```
1 = PE 启用，0 = PE 禁用。对于微型测试：仅前三行的列0被启用。

**`ipsum_ln_selectors.txt` / `opsum_ln_selectors.txt`（12x14）**
与 enables 格式相同。0 = 使用行平稳路径（PE到PE），1 = 使用 GLB/GIN/GON 路径。

**`ifmap_ids.txt`（12 行，每行 15 个值）**
```
0  0 31 31 31 31 31 31 31 31 31 31 31 31 31
1  0 31 31 31 31 ...
...
```
每行第一个值：4位行ID。剩余14个值：5位列ID。值15和31代表“无标签匹配”（禁用）。

**`filters_ids.txt` / `ipsum_ids.txt` / `opsum_ids.txt`（12x15）**
每行所有15个值都是4位ID。值为15 = 禁用。

**8. 每个配置文件控制什么（微型测试示例）**

对于微型测试层（`config/tiny/`）：

| 文件 | 用途 |
|---|---|
| `parameters.txt` | H=8,W=8,R=3,S=3,E=6,F=6,C=1,M=1,N=1,U=1,m=1,n=1,e=6,p=1,q=1,r=1,t=1 |
| `enables.txt` | 仅 PE(0,0), PE(1,0), PE(2,0) 启用；其余禁用 |
| `ipsum_ln_selectors.txt` | 控制 psum 是来自下方 PE（行平稳）还是来自 GLB |
| `opsum_ln_selectors.txt` | 控制 opsum 是去向上方 PE 还是去往 GON/GLB |
| `ifmap_ids.txt` | 第0,1,2行的行ID为0,1,2；第0列的列ID为0；其余=31（禁用） |
| `filters_ids.txt` | 每个PE的滤波器标签ID（第0列的行0->15, 行1->15, 行2->15；其余=15禁用） |
| `ipsum_ids.txt` | 每个PE的Ipsum标签ID |
| `opsum_ids.txt` | 每个PE的Opsum标签ID |
| `serial_data.txt` | 以上所有内容合并为一个比特流（反转，每行一个比特） |

**9. PE如何被启用/禁用**

每个PE都有一个由 `enable[i][j]` 控制的 `clk_gating` 模块：
```verilog
// 在 pe_wrapper.v 中
clk_gating clk_gating_inst (
    .enable(enable),
    .clk(clk),
    .gated_clk(gated_clk)
);
```
当 `enable=0` 时，PE的时钟被门控关闭，节省动态功耗。PE的内部状态被冻结。来自禁用PE的 `busy` 信号被忽略。

**10. NoC ID 如何被分配**

每个 GIN MCC (`gin_mcc.sv`) 都有一个可通过扫描编程的标签ID寄存器：
```verilog
scan_ff_Nbit #(.DATA_WIDTH(TAG_WIDTH)) scan_ff_Nbit_inst (
    .scan_in(scan_in_id),
    .q(q_id),                    // 此 PE 的行/列标签
    .scan_out(scan_out_id)
);

assign equal_tag = (q_id == tag);
assign data_out = enable_mid ? data_in : {DATA_WIDTH{1'b0}};
```

标签比较器将传入数据的行/列标签与通过扫描编程的 ID 进行匹配。只有具有匹配标签的 PE 接收数据。这就是 NoC 如何通过扫描链编程每个 PE 的标签 ID 来将数据路由到特定 PE。

对于微型测试，只有 PE (0,0), (1,0), (2,0) 被编程了有效的 ifmap ID；所有其他 PE 的 ID=31 或 15（超出范围 = 永不匹配）。