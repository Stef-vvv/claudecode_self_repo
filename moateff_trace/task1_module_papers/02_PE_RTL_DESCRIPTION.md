# Processing Element (PE): Register-Transfer-Level Description

## 1. Introduction and Architectural Role

The Processing Element (PE) is the fundamental compute unit of the Eyeriss accelerator. Each PE contains three local scratchpad memories (ifmap_spad, filter_spad, psum_spad), a signed 16-bit multiplier, a configurable truncator, an adder, and a controller FSM. The PE implements the core multiply-accumulate (MAC) operation of convolution: it multiplies an ifmap pixel by a filter weight, accumulates the result with a running partial sum, and passes partial sums vertically to neighboring PEs.

The PE array is organized as a 12-row by 14-column grid. Within each PE, the PE wrapper surrounds the core PE logic with FIFOs for ifmap, filter, and psum (ipsum/opsum) data. The PE controller is a six-state FSM that sequences through data loading, processing (MAC iterations), accumulation (receiving partial sums from below), stride (shifting the ifmap scratchpad), padding, and reload states. A zero-skipping mechanism gates the multiplier and scratchpad reads when ifmap pixels are zero, saving dynamic power.

## 2. PE Internal Structure and Data Path

### 2.1 Ifmap Scratchpad (ifmap_spad)

The ifmap scratchpad is a 12-deep shift register with both write and shift capability. It stores up to 12 ifmap pixels arranged as a linear buffer. The depth parameter `IFMAP_SPAD_DEPTH = 12` is derived from `q * S` (filter rows times stride), which determines the maximum number of ifmap pixels needed in flight.

The ifmap_spad operates as follows:
- **Write mode**: When `w_en` is asserted and `shift` is deasserted, the data input `din` is written to the next available position tracked by `w_addr`. The write pointer increments on each write.
- **Shift mode**: When `shift` is asserted, all entries shift left by one position (index i receives the value from index i+1). The write pointer decrements by one, effectively removing the oldest entry and making room for new data at the tail.
- **Read mode**: When `r_en` is asserted, the data at address `r_addr` is presented on `dout`. The read address is supplied by the PE controller as the loop counter `i_crnt`.
- **Full signal**: Asserted when `w_addr == spad_depth`, indicating the scratchpad has been completely filled to its configured depth.
- **Empty signal**: Asserted when `w_addr == r_addr`, meaning the write pointer has caught up to the read pointer or vice versa.
- **Reset**: On reset, the write pointer is cleared to 0, effectively marking the scratchpad as empty.

The shift register architecture supports the row-stationary dataflow, where a sliding window of ifmap pixels is maintained as the PE processes different filter rows. By shifting left, the oldest pixel is discarded and space is made for a new pixel from the next row.

### 2.2 Filter Scratchpad (filter_spad)

The filter scratchpad is a 224-deep Block RAM (BRAM), annotated with `(* ram_style = "block" *)` to guide synthesis toward BRAM inference. Its depth accommodates `p * q * S` filter weights -- the product of accumulators per PE (p), filter rows (q), and stride (S). At 16 bits per weight, this represents up to 224 filter weights that can be preloaded before processing begins.

The filter_spad is simpler than the ifmap_spad because it does not support shifting:
- **Write mode**: On `w_en`, data is written to `w_addr` and the write pointer increments. There is no shift capability.
- **Read mode**: On `r_en`, data at address `r_addr` (supplied by the controller as `i_crnt * p + j_crnt`) is read from the BRAM.
- **Full/Empty**: Same semantics as ifmap_spad -- full when write pointer reaches `spad_depth`, empty when write pointer equals read pointer.
- **Reset**: Clears the write pointer to 0.

The filter scratchpad is preloaded once per convolution pass (or per filter channel group) and is read repeatedly during the inner MAC loops. Because filters are reused across many ifmap pixels (weight stationary property), the filter_spad acts as a local weight cache that amortizes the cost of fetching weights from global buffers.

### 2.3 Partial Sum Scratchpad (psum_spad)

The psum_spad is a 24-deep dual-port-like BRAM (inferred through separate read and write address ports) that holds accumulated partial sums. Its depth of 24 is sized to hold `p * F` accumulators, where p is the number of accumulators and F is the filter width parameter.

The psum_spad has two distinctive features:
- **Write port**: On `posedge clk`, when `w_en` is asserted, the sum result is written to `w_addr`.
- **Read port**: On `negedge clk`, the data at `r_addr` is presented on `dout`. The use of negedge for reads ensures the data is stable before the next posedge write.
- **No reset, no full/empty**: Unlike the other scratchpads, psum_spad has no reset on the memory array itself, no full signal, and no empty signal. The PE controller manages accumulator validity through its FSM sequencing.

The psum_spad is central to the accumulation strategy: during MAC iterations, the PE reads an accumulator from psum_spad, adds the new product to it, and writes the result back to the same address. This read-modify-write cycle happens at the MAC throughput rate.

### 2.4 Zero-Skipping Unit

A dedicated zero_skipping module runs in parallel with the ifmap_spad. It maintains a 12-deep buffer of single-bit flags (`zero_buffer`), where each bit records whether the corresponding ifmap pixel in the scratchpad is zero. The module shadows the same write and shift operations as ifmap_spad:
- On write, it stores `(din == 0)` as a 1-bit flag.
- On shift, it shifts the flag buffer in lockstep with the ifmap_spad.
- The output `zero_flag` is the flag at the current read address.

The zero_flag is used to gate three operations:
1. The read enable of ifmap_spad: `r_en = (~zero_flag) & rd_data`
2. The read enable of filter_spad: `r_en = (~zero_flag) & rd_data`
3. The multiplier enable: `en_mul = (~zero_flag) & rd_data`

When an ifmap pixel is zero, the entire MAC pipeline (scratchpad reads + multiplication + accumulation write) for that pixel is suppressed. This is a data-gating power optimization that exploits the sparsity of activations (especially after ReLU in earlier layers, though this design uses no activation function at this stage).

## 3. MAC Pipeline: Five-Stage Data Path

The PE's computational data path is a deeply pipelined chain that processes one MAC operation per cycle. The stages are:

### Stage 1: Scratchpad Read
The ifmap pixel (`ifmap_from_spad`) and filter weight (`filter_from_spad`) are read from their respective scratchpads. The read addresses are computed by the controller: `ifmap_addr = i_crnt` and `filter_addr = i_crnt * p + j_crnt`. The read enable `rd_data` is gated by `~zero_flag`.

### Stage 2: Multiplier
The multiplier accepts two signed 16-bit operands (`mul_in1 = ifmap_from_spad`, `mul_in2 = filter_from_spad`) and produces a signed 32-bit product (`mul_result = x * y`). The multiplier is enabled by `en_mul_r`, which is the registered version of the enable signal. When disabled (or on reset), the product is zeroed. The multiplier registers its output on `negedge clk`.

### Stage 3: Truncator
The truncator extracts a 16-bit window from the 32-bit product. The `sel` input (tied to 5'b0 in this design) selects the starting bit position for the window. With `sel = 0`, the truncator outputs bits [0:15] of the product -- the least significant 16 bits. The truncator is purely combinational.

### Stage 4: Mux and Accumulation Select
A three-input selection chain determines what value enters the adder:
- **mux1**: Selects between the psum_spad output (`pusm_from_spad_w`) and the adder's own output (`sum_result`) via the `forward` bypass mechanism (described in Section 4).
- **mux2** (`reset_accumulation_r`): When the accumulation reset is asserted (on the first MAC of each accumulator, `i_crnt == 0`), the psum value is replaced with zero, effectively starting fresh accumulation.
- **mux3** (`accumulate_ipsum_rr`): Selects between the truncated product (`truncated_result`, for internal MAC) and the incoming partial sum from the PE below (`ipsum_pixel`, for vertical accumulation). This mux implements the choice between local MAC and vertical accumulation.

The adder then sums the output of mux3 (`adder_in1`, the new contribution) and the registered psum value from mux1 (`mux1_out_r`, delayed by one pipeline stage via flopr reg3). The combinational sum (`sum_result`) feeds back to mux1 (forward) and to the psum_spad write port.

### Stage 5: Output Mux and Push
The final output `opsum_pixel` is gated by the `pad_rr` signal: when padding, the output is forced to zero. Otherwise, it carries the adder sum result. The `push_opsum` and `pop_ipsum` signals are asserted when `accumulate_ipsum_rr | pad_rr` is true, meaning data flows out of the PE either during vertical accumulation or during padding.

## 4. The Forward Bypass Mechanism

The psum_spad has a single-cycle read latency: the read address `r_addr` is presented on one cycle, and the data appears on `dout` on the next cycle. However, the MAC pipeline writes a result to the same address one cycle after reading it (read at cycle T, write at cycle T+2 after pipeline delay). If the next MAC operation needs to read from the same accumulator address (same `j_crnt`), it would read stale data from the BRAM instead of the just-computed value.

The forward bypass solves this hazard:
- The write address (`psum_addr_rr`) and write enable (`wr_psum_rr`) are delayed by two pipeline stages (through reg1 and reg2).
- The forward signal is asserted when `wr_psum_rr & (psum_addr_r == psum_addr_rr)` -- that is, when a write is happening at the same address as the current read.
- When `forward = 1`, mux1 selects `sum_result` (the adder output) instead of `pusm_from_spad_w` (the BRAM output). This bypasses the BRAM and uses the freshly computed value directly.

This mechanism is essential for correct accumulation when the same accumulator index (j) repeats across consecutive filter rows or channels.

## 5. The PE Controller: Six-State FSM

The PE controller is the sequencer for the PE's operations. It runs on `negedge clk` (register updates) with combinational next-state logic, producing control signals for the scratchpads, multiplier, accumulator, and psum_spad.

### 5.1 State IDLE
The controller waits in IDLE with `busy = 0`. It transitions to PROCESS when the external `start` signal is asserted. The start signal is driven by `~spads_empty`, meaning processing begins as soon as both the filter and ifmap scratchpads contain data.

### 5.2 State PROCESS: Inner MAC Loops
The PROCESS state implements the core convolution inner loops. Each cycle in PROCESS performs one MAC operation. The state iterates through two nested counters:

- **i_crnt** (ifmap index, 0 to S*q - 1): The outer PROCESS loop iterates over the ifmap pixel window. There are `S * q` ifmap pixels (stride times filter rows) that must be multiplied against each filter weight.
- **j_crnt** (accumulator index, 0 to p-1): The inner PROCESS loop iterates over the p accumulators. For each ifmap pixel, the PE multiplies it by p different filter weights and accumulates the results into p separate partial sums.

The total number of MAC operations per PROCESS phase is `S * q * p`. The address generation reflects the data layout:
- `ifmap_addr = i_crnt`: The ifmap pixel index.
- `filter_addr = i_crnt * p + j_crnt`: For a given ifmap pixel i, the p filter weights are stored contiguously starting at offset i*p.
- `psum_addr = j_crnt`: The accumulator index (each of the p accumulators is at its own address).

Control signals during PROCESS:
- When `i_crnt == 0` (first ifmap pixel for this accumulator set), `reset_accumulation = 1` to zero the accumulator before adding the first product.
- `rd_data = 1` to enable scratchpad reads.
- `wr_psum = 1` to write back the accumulated result to psum_spad.

The state advances: j_crnt increments first (inner loop), wrapping back to 0 when it reaches p. When j wraps and i reaches S*q, both counters reset to 0 and the state transitions to ACCUMULATE.

### 5.3 State ACCUMULATE: Vertical Partial Sum Flow

The ACCUMULATE state handles the vertical flow of partial sums between PEs. Each row of PEs computes partial sums for different filter rows (or filter groups). After completing its local MAC iterations, a PE must incorporate the partial sum from the PE directly below it in the array (higher row index).

The accumulation is gated by two flow-control conditions:
- `~ipsum_fifo_empty`: The input partial sum FIFO from the PE below must have data.
- `~opsum_fifo_full`: The output partial sum FIFO upward must have space.

When both conditions are satisfied, `accumulate_ipsum = 1`, which (after two pipeline stages) causes mux3 to select `ipsum_pixel` instead of `truncated_result`. The adder then adds the incoming partial sum to the local accumulator value.

The accumulator index j_crnt is used to iterate through all p accumulators. When j_crnt reaches p, it wraps to 0 and the F counter is checked:

- **F_crnt**: Counts how many times the STRIDE-ACCUMULATE cycle has completed. Each cycle processes one filter column/row group. When F_crnt reaches F, all filter groups are done and the state transitions to PADDING.
- **V reload**: V (equal to `p[1:0] * F[1:0]`) is reloaded into V_crnt for padding countdown.

If F_crnt has not reached F, it increments and the state transitions to STRIDE.

### 5.4 State STRIDE: Sliding the Ifmap Window

The STRIDE state shifts the ifmap_spad by exactly one position to slide the ifmap window. It asserts `shift = 1` for one cycle and counts U_crnt from 0 to U*q - 1. The shift is performed U*q times total across all STRIDE visits.

The counter U_crnt increments each STRIDE cycle. When it reaches U*q, U_crnt resets to 0 and the state transitions back to PROCESS, beginning a new round of MAC computations with the shifted ifmap window. This implements the convolution stride: the ifmap window slides by U pixels (stride) after each filter row is processed.

### 5.5 State PADDING: Handling Filter Boundaries

The PADDING state handles the padding (zero-filling) at filter row boundaries. When V_crnt is zero, padding is complete and the state transitions to LOAD. When V_crnt is non-zero, `pad = 1` is asserted (which forces `opsum_pixel = 0` in the PE top level), V_crnt increments, and the state remains in PADDING.

The padding behavior ensures that when the convolution window extends beyond the ifmap boundaries, the PE produces zero output rather than reading invalid ifmap data.

### 5.6 State LOAD: Preparing for Next Pass

The LOAD state resets the ifmap_spad (`reset_ifmap_spad = 1`), clearing it for new data. It also manages the n_crnt counter:

- If n_crnt reaches n-1, the current ifmap group is complete. Both filter and ifmap scratchpads are reset (`reset_filter_spad = 1`), n_crnt resets to 0, and the PE returns to IDLE.
- Otherwise, n_crnt increments and the PE returns to PROCESS, reusing the same filter weights against a new ifmap group (channel group).

## 6. PE Wrapper: FIFO Interface to NoC

The PE wrapper encapsulates the core PE with input and output FIFOs, providing a standard streaming interface to the Network-on-Chip (NoC). It also implements clock gating.

### 6.1 Clock Gating

The wrapper instantiates a `clk_gating` module. The `enable` signal (from the PE array's scan chain) gates the clock to the PE. When `enable = 0`, the PE is clock-gated off, saving power. The gated clock `gated_clk` drives the PE core and all its FIFOs.

### 6.2 FIFO Configuration

Four synchronous FIFOs surround the PE core:

- **ifmap_fifo**: Width conversion from `DATA_WIDTH_IFMAP` (16 bits) to `DATA_WIDTH` (16 bits), depth `IFMAP_FIFO_DEPTH` (8). This FIFO provides rate decoupling between the NoC delivery rate and the PE consumption rate.
- **filter_fifo**: Width conversion from `DATA_WIDTH_FILTER` (64 bits) to `DATA_WIDTH` (16 bits), depth `FILTER_FIFO_DEPTH` (8). Note the width mismatch: the NoC delivers filters in 64-bit words (4 weights packed together), and the FIFO automatically unpacks them to 16-bit for the PE.
- **ipsum_fifo**: Width conversion from `DATA_WIDTH_PSUM` (64 bits) to `DATA_WIDTH` (16 bits), depth `PSUM_FIFO_DEPTH` (8). Input partial sums arrive packed at 64 bits and are unpacked to 16 bits.
- **opsum_fifo**: Width conversion from `DATA_WIDTH` (16 bits) to `DATA_WIDTH_PSUM` (64 bits), depth `PSUM_FIFO_DEPTH` (8). Output partial sums are packed from 16 bits to 64 bits for transmission on the NoC.

### 6.3 Flow Control

The wrapper implements ready/valid flow control between the FIFOs and the PE core:
- **Data input**: `pop_filter` is asserted when the filter_spad is not full and the filter FIFO is not empty: `(~filter_spad_full) & (~filter_fifo_empty)`. Similarly for ifmap.
- **Data output**: The push_opsum and pop_ipsum signals connect directly through to the FIFOs. The `opsum_fifo_full` signal gates the ACCUMULATE state in the PE controller.

The `opsum_fifo_full` is a critical backpressure signal: in the ACCUMULATE state, the PE only consumes an ipsum and produces an opsum when both `~ipsum_fifo_empty` and `~opsum_fifo_full` are true, preventing FIFO overflow or underflow.

## 7. The 12x14 PE Array: pe_array.sv

### 7.1 Array Organization

The PE array is a 2D grid of 12 rows by 14 columns of PE wrappers. Each PE wrapper instance is identical, parameterized by the same PE parameters but receiving unique enable bits and data connections from the NoC.

### 7.2 Scan Chain Configuration

Three scan chains run through the PE array, one per row, delivering configuration bits:
- **enable[0:11][0:13]**: Individual PE clock-enable bits, allowing selective power-down of unused PEs.
- **ipsum_ln_sel[0:11][0:13]**: Selects whether the PE's partial sum input comes from the NoC (GIN) or from the PE below it (vertical dataflow). When `ipsum_ln_sel[i][j] = 1`, the PE takes its input partial sum from the GIN (the global input network). When 0, it takes it from the PE at row i+1 (below).
- **opsum_ln_sel[0:11][0:13]**: Selects whether the PE's partial sum output goes to the NoC (GON) or to the PE above it. When `opsum_ln_sel[i][j] = 1`, the PE sends its output to the GON (global output network). When 0, it sends it to the PE at row i-1 (above).

The scan chains are organized as: 12 enable bits -> 12 ipsum_ln_sel bits -> 12 opsum_ln_sel bits -> (GIN/GON scan chain). Each row's scan_ff_Nbit register holds 14 bits (one per column), and the scan output of one row feeds the scan input of the next row.

### 7.3 Vertical Partial Sum Dataflow

The partial sum dataflow between PEs is the defining feature of the row-stationary architecture. The connection pattern for PE at (i, j) is:

- **ipsum (partial sum input)**: If `ipsum_ln_sel[i][j] == 1`, the input comes from `ipsum_from_gin[i][j]` (global input network). Otherwise, it comes from `opsum_from_pe[i+1][j]` -- the output of the PE directly below (row i+1, same column j).
- **opsum (partial sum output)**: If `opsum_ln_sel[i][j] == 1`, the output goes to `pop_opsum_from_pe_to_gon[i][j]` (global output network). Otherwise, it goes upward to the PE at row i-1 via the `ipsum` input of that PE.

This creates vertical accumulation chains within each column. The bottom-most PE in a chain receives its ipsum from the GIN, processes it, and passes its opsum upward. The top-most PE in the chain sends its opsum to the GON for readout. The `ipsum_ln_sel` and `opsum_ln_sel` configuration determines where these chain boundaries lie.

The push/pop handshakes implement the vertical flow:
- **Push to PE above** (ipsum path): `push_ipsum = ipsum_ln_sel[i][j] ? push_ipsum_to_pe_from_gin[i][j] : ((~opsum_pe_fifo_empty[i+1][j]) & (~ipsum_pe_fifo_full[i][j]))`. When not using GIN, the push is enabled only when the source below has data and the destination above has space.
- **Pop from PE** (opsum path): `pop_opsum = opsum_ln_sel[i][j] ? pop_opsum_from_pe_to_gon[i][j] : ((~opsum_pe_fifo_empty[i][j]) & (~ipsum_pe_fifo_full[i-1][j]))`. When not using GON, the pop is enabled only when the current PE has data and the destination above has space.

### 7.4 GIN and GON Instances

The PE array instantiates three GIN wrappers (ifmap, filter, ipsum) and one GON wrapper (opsum). Each GIN receives data and tags from the NoC and distributes them to the appropriate PE columns based on tag matching. The GON collects data from PE columns and sends it back to the NoC. These are described in detail in the NoC documentation.

The GIN data outputs connect to each PE's input FIFO: `ifmap_from_gin[i][j]` goes to the ifmap_fifo, `filter_from_gin[i][j]` to the filter_fifo, `ipsum_from_gin[i][j]` to the ipsum_fifo. The GON reads from each PE's opsum_fifo: `opsum_from_pe[i][j]` is the PE's output data.

Ready signals propagate from PEs back to the GIN/GON for flow control:
- `ifmap_gin_ready[i][j] = ~ifmap_pe_fifo_full[i][j]` (we can accept data when FIFO is not full)
- `filter_gin_ready[i][j] = ~filter_pe_fifo_full[i][j]`
- `ipsum_gin_ready[i][j] = ~ipsum_pe_fifo_full[i][j]`
- `opsum_gon_ready[i][j] = ~opsum_pe_fifo_empty[i][j]` (we have data to send when FIFO is not empty)

## 8. Timing and Pipeline Summary

The PE operates on `negedge clk` for its controller state registers, scratchpad reads, and multiplier. The psum_spad writes on `posedge clk`. This mixed-edge design allows:
1. The controller produces addresses on negedge.
2. Scratchpads read data on negedge (same edge as controller).
3. Multiplier produces product on negedge.
4. Adder is combinational.
5. Psum_spad writes the result on posedge (half cycle after the read), ensuring the data is stable.

The two pipeline register stages (reg1 and reg2, each a `flopr`) align the psum_spad address, write enable, accumulate_ipsum, and pad signals across the multiplier and adder pipeline depth. Specifically:
- **reg1** delays the control signals by one cycle (aligning with the multiplier latency).
- **reg2** delays by another cycle (aligning with the truncator + mux latency).

The forward bypass path (scanning whether the write address in reg2 matches the current read address) is combinational and resolves in the same cycle as the psum_spad read, allowing the bypassed value to reach the adder in time.

## 9. Parameter Relationships

The PE's configuration parameters form a carefully balanced system:

- **S (stride)**: Determines the ifmap_spad depth needed (q * S) and the number of MAC iterations per filter position.
- **F**: The number of filter groups processed before padding. V = p[1:0] * F[1:0] is used as the padding cycle count.
- **U (stride for sliding window)**: Controls how many times the STRIDE state executes (U * q shifts total).
- **p**: Number of accumulators -- the number of output channels this PE processes in parallel. Determines psum_spad usage.
- **q**: Number of filter rows -- determines the ifmap pixel window size (S * q).
- **n**: Number of ifmap groups processed before reloading filters.

The product `p * q * S` determines filter_spad depth (maximum 224). The parameter V = `p[1:0] * F[1:0]` is a 2-bit quantity used for padding cycle counting.

## 10. Zero-Skipping Impact on Data Flow

The zero-skipping logic is a power optimization that does not affect functional correctness. When a zero ifmap pixel is detected:

1. `zero_flag = 1` is asserted for that address.
2. The ifmap_spad read enable is gated off -- no data is read, saving BRAM read power.
3. The filter_spad read enable is gated off -- the corresponding filter weight is not read, saving BRAM read power.
4. The multiplier enable is gated off -- the multiplier output is forced to zero, saving multiplier switching power.
5. Since the truncated product is zero, the adder simply passes through the existing accumulator value unchanged (adding zero).
6. The psum_spad write still occurs, writing back the unchanged accumulator value.

This preserves the correct accumulator value while avoiding unnecessary toggling in the data path. The zero_skipping module maintains a shadow copy of the ifmap_spad's occupancy via the same write and shift operations, ensuring the zero flags remain aligned with the ifmap data.


































**处理单元（PE）：寄存器传输级描述**

**1. 简介与架构角色**

处理单元（PE）是 Eyeriss 加速器的基本计算单元。每个 PE 包含三个本地暂存存储器（ifmap_spad、filter_spad、psum_spad）、一个有符号 16 位乘法器、一个可配置截断器、一个加法器以及一个控制器 FSM。PE 实现了卷积的核心乘加（MAC）操作：它将一个 ifmap 像素乘以一个滤波器权重，将结果与运行中的部分和累加，并将部分和垂直传递给相邻的 PE。

PE 阵列被组织为一个 12 行乘 14 列的网格。在每个 PE 内部，PE 封装器用 ifmap、滤波器和 psum（ipsum/opsum）数据的 FIFO 包围核心 PE 逻辑。PE 控制器是一个六状态 FSM，它按顺序经历数据加载、处理（MAC 迭代）、累积（接收来自下方的部分和）、步长（移位 ifmap 暂存器）、填充和重载状态。当 ifmap 像素为零时，零值跳过机制会对乘法器和暂存器读取进行门控，以节省动态功耗。

**2. PE 内部结构与数据路径**

**2.1 Ifmap 暂存器（ifmap_spad）**

ifmap 暂存器是一个深度为 12 的移位寄存器，具有写入和移位能力。它最多存储 12 个 ifmap 像素，排列成一个线性缓冲区。深度参数 `IFMAP_SPAD_DEPTH = 12` 源自 `q * S`（滤波器行数乘以步长），这决定了所需在途 ifmap 像素的最大数量。

ifmap_spad 的操作如下：
-   **写模式**：当 `w_en` 被断言且 `shift` 被取消断言时，数据输入 `din` 被写入由 `w_addr` 跟踪的下一个可用位置。每次写入时写指针递增。
-   **移位模式**：当 `shift` 被断言时，所有条目向左移动一个位置（索引 i 接收来自索引 i+1 的值）。写指针减一，有效地移除最旧的条目，并为尾部的新数据腾出空间。
-   **读模式**：当 `r_en` 被断言时，位于地址 `r_addr` 的数据呈现在 `dout` 上。读地址由 PE 控制器作为循环计数器 `i_crnt` 提供。
-   **满信号**：当 `w_addr == spad_depth` 时断言，表示暂存器已完全填满到其配置的深度。
-   **空信号**：当 `w_addr == r_addr` 时断言，意味着写指针已追上读指针或反之。
-   **复位**：复位时，写指针被清零，有效地将暂存器标记为空。

移位寄存器架构支持行平稳数据流，其中随着 PE 处理不同的滤波器行，会维护一个 ifmap 像素的滑动窗口。通过向左移位，最旧的像素被丢弃，并为来自下一行的新像素腾出空间。

**2.2 滤波器暂存器（filter_spad）**

滤波器暂存器是一个深度为 224 的块 RAM（BRAM），用 `(* ram_style = "block" *)` 注解以引导综合工具推断为 BRAM。其深度可容纳 `p * q * S` 个滤波器权重——即每个 PE 的累加器数（p）、滤波器行数（q）和步长（S）的乘积。以每个权重 16 位计算，这代表最多 224 个可以在处理开始前预加载的滤波器权重。

filter_spad 比 ifmap_spad 更简单，因为它不支持移位：
-   **写模式**：在 `w_en` 上，数据被写入 `w_addr`，写指针递增。没有移位能力。
-   **读模式**：在 `r_en` 上，位于地址 `r_addr`（由控制器作为 `i_crnt * p + j_crnt` 提供）的数据从 BRAM 中读出。
-   **满/空**：与 ifmap_spad 语义相同——当写指针到达 `spad_depth` 时满，当写指针等于读指针时空。
-   **复位**：将写指针清零。

滤波器暂存器在每个卷积趟（或每个滤波器通道组）预加载一次，并在内部 MAC 循环期间被重复读取。由于滤波器跨许多 ifmap 像素被重用（权重平稳属性），filter_spad 充当本地权重缓存，平摊了从全局缓冲区取权重的高昂成本。

**2.3 部分和暂存器（psum_spad）**

psum_spad 是一个深度为 24 的类双端口 BRAM（通过独立的读写地址端口推断），用于保存累积的部分和。其深度 24 的大小被设计为容纳 `p * F` 个累加器，其中 p 是累加器数量，F 是滤波器宽度参数。

psum_spad 有两个显著特点：
-   **写端口**：在 `posedge clk` 上，当 `w_en` 被断言时，和结果被写入 `w_addr`。
-   **读端口**：在 `negedge clk` 上，位于 `r_addr` 的数据呈现在 `dout` 上。在 negedge 上进行读取可确保数据在下一个 posedge 写入之前稳定。
-   **无复位，无满/空**：与其他暂存器不同，psum_spad 在存储阵列本身上没有复位，没有满信号，也没有空信号。PE 控制器通过其 FSM 排序来管理累加器的有效性。

psum_spad 是累加策略的核心：在 MAC 迭代期间，PE 从 psum_spad 读取一个累加器，将新产品加到其中，并将结果写回同一地址。此读-修改-写周期以 MAC 吞吐率发生。

**2.4 零值跳过单元**

一个专用的 zero_skipping 模块与 ifmap_spad 并行运行。它维护一个深度为 12 的单比特标志缓冲区（`zero_buffer`），其中每个位记录暂存器中对应的 ifmap 像素是否为零。该模块镜像与 ifmap_spad 相同的写和移位操作：
-   在写入时，它将 `(din == 0)` 存储为一个 1 比特标志。
-   在移位时，它与 ifmap_spad 同步地移位标志缓冲区。
-   输出 `zero_flag` 是当前读地址处的标志。

zero_flag 用于门控三个操作：
1.  ifmap_spad 的读使能：`r_en = (~zero_flag) & rd_data`
2.  filter_spad 的读使能：`r_en = (~zero_flag) & rd_data`
3.  乘法器使能：`en_mul = (~zero_flag) & rd_data`

当一个 ifmap 像素为零时，该像素的整个 MAC 流水线（暂存器读取 + 乘法 + 累加写入）被抑制。这是一个数据门控功耗优化，它利用了激活值的稀疏性（尤其是在早期层经过 ReLU 之后，尽管此设计在此阶段不使用激活函数）。

**3. MAC 流水线：五级数据路径**

PE 的计算数据路径是一条深度流水化的链，每个周期处理一个 MAC 操作。各阶段如下：

**阶段 1：暂存器读取**
ifmap 像素（`ifmap_from_spad`）和滤波器权重（`filter_from_spad`）从各自的暂存器中读出。读地址由控制器计算：`ifmap_addr = i_crnt` 和 `filter_addr = i_crnt * p + j_crnt`。读使能 `rd_data` 由 `~zero_flag` 门控。

**阶段 2：乘法器**
乘法器接受两个有符号 16 位操作数（`mul_in1 = ifmap_from_spad`，`mul_in2 = filter_from_spad`），并产生一个有符号 32 位乘积（`mul_result = x * y`）。乘法器由 `en_mul_r` 使能，`en_mul_r` 是使能信号的寄存器版本。当被禁用（或复位）时，乘积被清零。乘法器在 `negedge clk` 上寄存其输出。

**阶段 3：截断器**
截断器从 32 位乘积中提取一个 16 位窗口。`sel` 输入（在此设计中固定为 5'b0）选择窗口的起始位位置。当 `sel = 0` 时，截断器输出乘积的位 [0:15]——最低有效 16 位。截断器是纯组合逻辑的。

**阶段 4：多路复用与累加选择**
一个三输入选择链决定哪个值进入加法器：
-   **mux1**：通过 `forward` 旁路机制（在第 4 节中描述），在 psum_spad 输出（`pusm_from_spad_w`）和加法器自身输出（`sum_result`）之间进行选择。
-   **mux2**（`reset_accumulation_r`）：当累加复位被断言时（在每个累加器的第一个 MAC，`i_crnt == 0`），psum 值被替换为零，有效地开始新的累加。
-   **mux3**（`accumulate_ipsum_rr`）：在截断后的乘积（`truncated_result`，用于内部 MAC）和来自下方 PE 的传入部分和（`ipsum_pixel`，用于垂直累加）之间进行选择。此 mux 实现了本地 MAC 和垂直累加之间的选择。

然后，加法器将 mux3 的输出（`adder_in1`，新贡献）与来自 mux1 的寄存器 psum 值（`mux1_out_r`，通过 flopr reg3 延迟一个流水线阶段）相加。组合和（`sum_result`）反馈回 mux1（前向）和 psum_spad 写端口。

**阶段 5：输出 Mux 与推送**
最终输出 `opsum_pixel` 由 `pad_rr` 信号门控：当处于填充模式时，输出被强制为零。否则，它携带加法器求和结果。当 `accumulate_ipsum_rr | pad_rr` 为真时，`push_opsum` 和 `pop_ipsum` 信号被断言，意味着数据在垂直累加期间或填充期间流出 PE。

**4. 前向旁路机制**

psum_spad 具有单周期读延迟：读地址 `r_addr` 在一个周期给出，数据在下一个周期出现在 `dout` 上。然而，MAC 流水线在读取后的一个周期将结果写回同一地址（在周期 T 读取，在流水线延迟后在周期 T+2 写入）。如果下一个 MAC 操作需要从相同的累加器地址（相同的 `j_crnt`）读取，它将从 BRAM 中读到陈旧的数据，而不是刚刚计算出的值。

前向旁路解决了这个冒险：
-   写地址（`psum_addr_rr`）和写使能（`wr_psum_rr`）被两个流水线阶段（通过 reg1 和 reg2）延迟。
-   当 `wr_psum_rr & (psum_addr_r == psum_addr_rr)` 时，前向信号被断言——也就是说，当一次写操作正在与当前读操作相同的地址发生时。
-   当 `forward = 1` 时，mux1 选择 `sum_result`（加法器输出）而不是 `pusm_from_spad_w`（BRAM 输出）。这绕过了 BRAM，直接使用新计算出的值。

当相同的累加器索引（j）跨连续的滤波器行或通道重复时，此机制对于正确累加至关重要。

**5. PE 控制器：六状态 FSM**

PE 控制器是 PE 操作的定序器。它运行在 `negedge clk` 上（寄存器更新），并配合组合逻辑产生下一个状态，为暂存器、乘法器、累加器和 psum_spad 产生控制信号。

**5.1 状态 IDLE**
控制器在 IDLE 状态下等待，`busy = 0`。当外部 `start` 信号被断言时，它转换到 PROCESS。start 信号由 `~spads_empty` 驱动，意味着只要滤波器和 ifmap 两个暂存器都包含数据，处理就开始。

**5.2 状态 PROCESS：内部 MAC 循环**
PROCESS 状态实现核心的卷积内层循环。PROCESS 中的每个周期执行一个 MAC 操作。该状态遍历两个嵌套计数器：

-   **i_crnt**（ifmap 索引，0 到 S*q - 1）：外层 PROCESS 循环遍历 ifmap 像素窗口。有 `S * q` 个 ifmap 像素（步长乘以滤波器行数）必须与每个滤波器权重相乘。
-   **j_crnt**（累加器索引，0 到 p-1）：内层 PROCESS 循环遍历 p 个累加器。对于每个 ifmap 像素，PE 将其乘以 p 个不同的滤波器权重，并将结果累加到 p 个独立的部分和中。

每个 PROCESS 阶段的 MAC 操作总数是 `S * q * p`。地址生成反映了数据布局：
-   `ifmap_addr = i_crnt`：ifmap 像素索引。
-   `filter_addr = i_crnt * p + j_crnt`：对于给定的 ifmap 像素 i，p 个滤波器权重从偏移量 i*p 开始连续存储。
-   `psum_addr = j_crnt`：累加器索引（p 个累加器中的每一个都在自己的地址上）。

PROCESS 期间的控制信号：
-   当 `i_crnt == 0`（此累加器组的第一个 ifmap 像素）时，`reset_accumulation = 1`，在添加第一个产品之前将累加器清零。
-   `rd_data = 1`，以启用暂存器读取。
-   `wr_psum = 1`，将累加结果写回 psum_spad。

状态推进：j_crnt 首先递增（内层循环），当到达 p 时回绕到 0。当 j 回绕且 i 到达 S*q 时，两个计数器都复位到 0，状态转换到 ACCUMULATE。

**5.3 状态 ACCUMULATE：垂直部分和流动**

ACCUMULATE 状态处理 PE 之间的部分和垂直流动。每行 PE 为不同的滤波器行（或滤波器组）计算部分和。在完成其本地 MAC 迭代后，一个 PE 必须合并来自阵列中直接在其下方的 PE（更高行索引）的部分和。

累加由两个流控制条件门控：
-   `~ipsum_fifo_empty`：来自下方 PE 的输入部分和 FIFO 必须有数据。
-   `~opsum_fifo_full`：向上的输出部分和 FIFO 必须有空间。

当两个条件都满足时，`accumulate_ipsum = 1`，这（在两个流水线阶段之后）导致 mux3 选择 `ipsum_pixel` 而不是 `truncated_result`。然后加法器将传入的部分和加到本地累加器值上。

累加器索引 j_crnt 用于遍历所有 p 个累加器。当 j_crnt 到达 p 时，它回绕到 0，并检查 F 计数器：

-   **F_crnt**：统计 STRIDE-ACCUMULATE 周期已完成的次数。每个周期处理一个滤波器列/行组。当 F_crnt 到达 F 时，所有滤波器组都已完成，状态转换到 PADDING。
-   **V 重载**：V（等于 `p[1:0] * F[1:0]`）被重载到 V_crnt 中，用于填充倒计时。

如果 F_crnt 尚未到达 F，它递增，状态转换到 STRIDE。

**5.4 状态 STRIDE：滑动 Ifmap 窗口**

STRIDE 状态将 ifmap_spad 恰好移位一个位置，以滑动 ifmap 窗口。它断言 `shift = 1` 一个周期，并从 0 到 U*q - 1 计数 U_crnt。在所有 STRIDE 访问中，移位总共执行 U*q 次。

计数器 U_crnt 在每个 STRIDE 周期递增。当它到达 U*q 时，U_crnt 复位到 0，状态转换回 PROCESS，开始一轮新的使用移位后 ifmap 窗口的 MAC 计算。这实现了卷积步长：在每个滤波器行被处理后，ifmap 窗口滑动 U 个像素（步长）。

**5.5 状态 PADDING：处理滤波器边界**

PADDING 状态处理滤波器行边界处的填充（零填充）。当 V_crnt 为零时，填充完成，状态转换到 LOAD。当 V_crnt 非零时，`pad = 1` 被断言（这强制 PE 顶层的 `opsum_pixel = 0`），V_crnt 递增，状态保持在 PADDING。

填充行为确保当卷积窗口延伸到 ifmap 边界之外时，PE 产生零输出，而不是读取无效的 ifmap 数据。

**5.6 状态 LOAD：为下一个处理趟做准备**

LOAD 状态复位 ifmap_spad（`reset_ifmap_spad = 1`），为其清除以接收新数据。它还管理 n_crnt 计数器：

-   如果 n_crnt 到达 n-1，则当前 ifmap 组完成。滤波器和 ifmap 两个暂存器都被复位（`reset_filter_spad = 1`），n_crnt 复位到 0，PE 返回 IDLE。
-   否则，n_crnt 递增，PE 返回 PROCESS，将相同的滤波器权重重用于一个新的 ifmap 组（通道组）。

**6. PE 封装器：与 NoC 的 FIFO 接口**

PE 封装器用输入和输出 FIFO 封装核心 PE，为片上网络（NoC）提供标准的流式接口。它还实现了时钟门控。

**6.1 时钟门控**

封装器例化了一个 `clk_gating` 模块。`enable` 信号（来自 PE 阵列的扫描链）门控进入 PE 的时钟。当 `enable = 0` 时，PE 的时钟被门控关闭，节省功耗。门控时钟 `gated_clk` 驱动 PE 核心及其所有 FIFO。

**6.2 FIFO 配置**

四个同步 FIFO 环绕 PE 核心：

-   **ifmap_fifo**：位宽转换从 `DATA_WIDTH_IFMAP`（16 位）到 `DATA_WIDTH`（16 位），深度 `IFMAP_FIFO_DEPTH`（8）。此 FIFO 在 NoC 交付速率和 PE 消耗速率之间提供速率解耦。
-   **filter_fifo**：位宽转换从 `DATA_WIDTH_FILTER`（64 位）到 `DATA_WIDTH`（16 位），深度 `FILTER_FIFO_DEPTH`（8）。注意位宽不匹配：NoC 以 64 位字（4 个权重打包在一起）交付滤波器，FIFO 自动将其解包为 16 位供 PE 使用。
-   **ipsum_fifo**：位宽转换从 `DATA_WIDTH_PSUM`（64 位）到 `DATA_WIDTH`（16 位），深度 `PSUM_FIFO_DEPTH`（8）。传入的部分和以 64 位打包到达，并被解包为 16 位。
-   **opsum_fifo**：位宽转换从 `DATA_WIDTH`（16 位）到 `DATA_WIDTH_PSUM`（64 位），深度 `PSUM_FIFO_DEPTH`（8）。传出的部分和从 16 位打包到 64 位，以便在 NoC 上传输。

**6.3 流控制**

封装器在 FIFO 和 PE 核心之间实现 ready/valid 流控制：
-   **数据输入**：当 filter_spad 不满且滤波器 FIFO 不空时，即 `(~filter_spad_full) & (~filter_fifo_empty)` 时，`pop_filter` 被断言。ifmap 类似。
-   **数据输出**：push_opsum 和 pop_ipsum 信号直通连接到 FIFO。`opsum_fifo_full` 信号门控 PE 控制器中的 ACCUMULATE 状态。

`opsum_fifo_full` 是一个关键的反压信号：在 ACCUMULATE 状态，只有当 `~ipsum_fifo_empty` 和 `~opsum_fifo_full` 都为真时，PE 才消耗一个 ipsum 并产生一个 opsum，以防止 FIFO 溢出或下溢。

**7. 12x14 PE 阵列：pe_array.sv**

**7.1 阵列组织**

PE 阵列是一个 12 行乘 14 列的 PE 封装器二维网格。每个 PE 封装器实例是相同的，由相同的 PE 参数进行参数化，但接收来自 NoC 的唯一使能位和数据连接。

**7.2 扫描链配置**

三条扫描链贯穿 PE 阵列，每行一条，传递配置位：
-   **enable[0:11][0:13]**：各个 PE 的时钟使能位，允许选择性关闭未使用 PE 的电源。
-   **ipsum_ln_sel[0:11][0:13]**：选择 PE 的部分和输入是来自 NoC（GIN）还是来自其下方的 PE（垂直数据流）。当 `ipsum_ln_sel[i][j] = 1` 时，PE 从 GIN（全局输入网络）获取其输入部分和。当为 0 时，它从位于行 i+1 的 PE（下方）获取。
-   **opsum_ln_sel[0:11][0:13]**：选择 PE 的部分和输出是去往 NoC（GON）还是其上方 PE。当 `opsum_ln_sel[i][j] = 1` 时，PE 将其输出发送到 GON（全局输出网络）。当为 0 时，它将其发送到位于行 i-1 的 PE（上方）。

扫描链的组织为：12 个使能位 -> 12 个 ipsum_ln_sel 位 -> 12 个 opsum_ln_sel 位 ->（GIN/GON 扫描链）。每行的 scan_ff_Nbit 寄存器保存 14 位（每列一个），并且一行的扫描输出馈送下一行的扫描输入。

**7.3 垂直部分和数据流**

PE 之间的部分和数据流是行平稳架构的决定性特征。位于（i, j）的 PE 的连接模式是：

-   **ipsum（部分和输入）**：如果 `ipsum_ln_sel[i][j] == 1`，则输入来自 `ipsum_from_gin[i][j]`（全局输入网络）。否则，它来自 `opsum_from_pe[i+1][j]`——直接在下方的 PE 的输出（行 i+1，相同列 j）。
-   **opsum（部分和输出）**：如果 `opsum_ln_sel[i][j] == 1`，则输出去往 `pop_opsum_from_pe_to_gon[i][j]`（全局输出网络）。否则，它通过该 PE 的 `ipsum` 输入向上到达位于行 i-1 的 PE。

这在每列内创建了垂直累加链。链中最底部的 PE 从 GIN 接收其 ipsum，处理它，并将其 opsum 向上传递。链中最顶部的 PE 将其 opsum 发送到 GON 以进行读出。`ipsum_ln_sel` 和 `opsum_ln_sel` 配置决定了这些链的边界位于何处。

推/弹握手实现垂直流：
-   **向上方 PE 推送**（ipsum 路径）：`push_ipsum = ipsum_ln_sel[i][j] ? push_ipsum_to_pe_from_gin[i][j] : ((~opsum_pe_fifo_empty[i+1][j]) & (~ipsum_pe_fifo_full[i][j]))`。当不使用 GIN 时，仅当源下方有数据且目的地上方有空间时，推送才被启用。
-   **从 PE 弹出**（opsum 路径）：`pop_opsum = opsum_ln_sel[i][j] ? pop_opsum_from_pe_to_gon[i][j] : ((~opsum_pe_fifo_empty[i][j]) & (~ipsum_pe_fifo_full[i-1][j]))`。当不使用 GON 时，仅当当前 PE 有数据且目的地上方有空间时，弹出才被启用。

**7.4 GIN 和 GON 实例**

PE 阵列例化了三个 GIN 封装器（ifmap、filter、ipsum）和一个 GON 封装器（opsum）。每个 GIN 从 NoC 接收数据和标签，并基于标签匹配将它们分发到适当的 PE 列。GON 从 PE 列收集数据并将其发送回 NoC。这些在 NoC 文档中有详细描述。

GIN 数据输出连接到每个 PE 的输入 FIFO：`ifmap_from_gin[i][j]` 去到 ifmap_fifo，`filter_from_gin[i][j]` 去到 filter_fifo，`ipsum_from_gin[i][j]` 去到 ipsum_fifo。GON 从每个 PE 的 opsum_fifo 读取：`opsum_from_pe[i][j]` 是 PE 的输出数据。

ready 信号从 PE 传播回 GIN/GON 以进行流控制：
-   `ifmap_gin_ready[i][j] = ~ifmap_pe_fifo_full[i][j]`（当 FIFO 不满时我们可以接受数据）
-   `filter_gin_ready[i][j] = ~filter_pe_fifo_full[i][j]`
-   `ipsum_gin_ready[i][j] = ~ipsum_pe_fifo_full[i][j]`
-   `opsum_gon_ready[i][j] = ~opsum_pe_fifo_empty[i][j]`（当 FIFO 不空时我们有数据要发送）

**8. 时序与流水线摘要**

PE 的操作在其控制器状态寄存器、暂存器读取和乘法器上使用 `negedge clk`。psum_spad 在 `posedge clk` 上写入。这种混合沿设计允许：
1.  控制器在 negedge 产生地址。
2.  暂存器在 negedge 读取数据（与控制器同沿）。
3.  乘法器在 negedge 产生乘积。
4.  加法器是组合逻辑的。
5.  Psum_spad 在 posedge 写入结果（在读取后半个周期），确保数据稳定。

两个流水线寄存器阶段（reg1 和 reg2，各为一个 `flopr`）将 psum_spad 的地址、写使能、accumulate_ipsum 和 pad 信号对齐跨乘法器和加法器流水线深度。具体来说：
-   **reg1** 将控制信号延迟一个周期（与乘法器延迟对齐）。
-   **reg2** 再延迟一个周期（与截断器 + mux 延迟对齐）。

前向旁路路径（扫描 reg2 中的写地址是否与当前读地址匹配）是组合逻辑的，并在与 psum_spad 读取相同的周期内解析，允许旁路值及时到达加法器。

**9. 参数关系**

PE 的配置参数形成一个精心平衡的系统：

-   **S（步长）**：决定所需的 ifmap_spad 深度（q * S）以及每个滤波器位置的 MAC 迭代次数。
-   **F**：填充之前处理的滤波器组数。V = p[1:0] * F[1:0] 用作填充周期计数。
-   **U（滑动窗口的步长）**：控制 STRIDE 状态执行的次数（总共 U * q 次移位）。
-   **p**：累加器数——此 PE 并行处理的输出通道数。决定 psum_spad 的使用量。
-   **q**：滤波器行数——决定 ifmap 像素窗口大小（S * q）。
-   **n**：重新加载滤波器之前处理的 ifmap 组数。

乘积 `p * q * S` 决定 filter_spad 深度（最大 224）。参数 V = `p[1:0] * F[1:0]` 是一个用于填充周期计数的 2 位量。

**10. 零值跳过对数据流的影响**

零值跳过逻辑是一种不影响功能正确性的功耗优化。当检测到零 ifmap 像素时：

1.  对该地址，`zero_flag = 1` 被断言。
2.  ifmap_spad 读使能被门控——不读取任何数据，节省 BRAM 读功耗。
3.  filter_spad 读使能被门控——不读取对应的滤波器权重，节省 BRAM 读功耗。
4.  乘法器使能被门控——乘法器输出被强制为零，节省乘法器开关功耗。
5.  由于截断后的乘积为零，加法器简单地原样传递现有的累加器值（加零）。
6.  psum_spad 写入仍然发生，将未改变的累加器值写回。

这保持了正确的累加器值，同时避免了数据路径中不必要的翻转。zero_skipping 模块通过相同的写和移位操作维护 ifmap_spad 占用情况的影子副本，确保零标志与 ifmap 数据保持对齐。