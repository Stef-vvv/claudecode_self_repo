# Scheduler Module: Register-Transfer-Level Description

## 1. Module Overview and Architectural Role

The Scheduler is the top-level control unit of the Eyeriss accelerator. It orchestrates the entire convolution computation by sequencing data movement (NoC transactions), processing element (PE) execution, and partial sum accumulation across multiple passes. The Scheduler operates as a hierarchical finite state machine (FSM) with nine states, controlling two nested loop levels: an outer loop that advances through output-channel groups (M), ifmap rows (E), and ifmap groups (N), and an inner loop that advances through fine-grained filter groups (m) and input-channel groups (C). Each iteration of the inner loop triggers one "pass" -- the unit of work where the NoC delivers data to the PE array and the PEs compute one round of multiply-accumulate operations.

The module receives configuration parameters from a scan chain and produces identifier (ID) range outputs that tell the NoC which slices of the filter, ifmap, and partial sum tensors to fetch from global buffers. It also emits the control handshake signals (start_noc, busy, done, pass_done, ofmap_dump) that coordinate the entire system.

## 2. Parameterization

The Scheduler is parameterized by width parameters for all configuration and counter registers. The key parameters are:

- **E_WIDTH (6 bits)**: Width of the ifmap row count E, defining the maximum number of ifmap rows.
- **C_WIDTH (10 bits)**: Width of the input channel count C.
- **M_WIDTH (10 bits)**: Width of the output channel count M.
- **N_WIDTH (3 bits)**: Width of the ifmap group count N.
- **m_WIDTH (6 bits)**, **n_WIDTH (3 bits)**, **e_WIDTH (6 bits)**: Widths of the fine-grained loop bounds (m: filter groups within a pass, n: ifmap groups, e: ifmap rows within a group).
- **p_WIDTH (5 bits)**, **q_WIDTH (3 bits)**, **r_WIDTH (2 bits)**, **t_WIDTH (3 bits)**: Widths of the PE array dimensions and tiling factors (p: accumulators per PE, q: filter rows, r: filter channels per array, t: filter slices per array).

These widths are propagated from the top-level design and determine the bit widths of all internal counters and the ID range outputs.

## 3. Register File and State Encoding

The Scheduler maintains five internal counter registers and one state register, each with a present-value (`_crnt`) and next-value (`_nxt`) variant:

- **C_crnt / C_nxt**: The current input channel base offset for this pass group. It tracks which slice of the C input channels is being processed. Incremented by `q * r` on inner-loop completion.
- **M_crnt / M_nxt**: The current output channel base offset. It tracks which slice of the M output channels is being processed. Incremented by `m` on outer-loop completion.
- **N_crnt / N_nxt**: The current ifmap group base offset. It tracks which group of N ifmaps is being processed. Incremented by `n`.
- **E_crnt / E_nxt**: The current ifmap row base offset. It tracks which row within the ifmap is being processed, in increments of `e`.
- **m_crnt / m_nxt**: The fine-grained filter group counter within one output-channel pass. Incremented by `p * t` on each pass.

The state register `state_crnt` is of enumerated type `state_type` with nine values: `IDLE`, `CHECK`, `OUTER_LOOP`, `INNER_LOOP`, `START_PASS`, `PROCESS`, `PASS_DONE`, `DUMPING`, and `DONE`.

All registers are updated on the positive edge of `clk`, or asynchronously reset to zero/IDLE on the positive edge of `reset`. This is implemented in a single `always_ff` block. The next-state values (`state_nxt` and all `_nxt` counters) are computed in a single `always_comb` block, ensuring glitch-free transitions.

## 4. The Nine-State FSM: State-by-State Description

### 4.1 IDLE
The Scheduler begins in IDLE. All outputs (`start_noc`, `pass_done`, `busy`, `done`, `ofmap_dump`) are driven to zero. The next-state logic simply checks the external `start` signal: when `start` is asserted, the FSM transitions to CHECK. No counters are modified.

### 4.2 CHECK
The CHECK state is a synchronization point inserted between every pass and every outer-loop iteration. Its sole purpose is to wait for an external `start_pass` signal before proceeding. This handshake allows the external system (or testbench) to gate the start of each pass, for example to ensure that global buffer data is ready or that previous pipeline operations have drained. When `start_pass` is asserted, the FSM transitions to START_PASS. No counters are modified.

### 4.3 OUTER_LOOP
The OUTER_LOOP state implements the outermost three levels of the convolution loop nest: advancing through output channels (M), ifmap rows (E), and ifmap groups (N). The advancement logic is a cascade of overflow checks:

1. First, the state tests whether `M_crnt + m == M`. If this condition holds, the current M group has reached the total output channel count. In this case, M_crnt is reset to zero, and the state proceeds to test E.
2. It then tests whether `E_crnt + e >= E` (note: greater-than-or-equal, not just equal). If this holds, E_crnt is reset to zero, and the state proceeds to test N.
3. It then tests whether `N_crnt + n == N`. If this holds, N_crnt is reset to zero, and the FSM transitions to DONE (all convolution work complete).
4. If the E test fails, E_crnt is incremented by `e` and the FSM returns to CHECK.
5. If the M test fails at the top, M_crnt is incremented by `m` and the FSM returns to CHECK.
6. If the N test passes but either M or E was not at its limit, N_crnt is incremented by `n` and the FSM returns to CHECK.

The key insight is that M wraps before E wraps before N wraps, establishing a loop nest from innermost (M) to outermost (N): M varies fastest, then E, then N. This matches the dataflow ordering needed for the row-stationary architecture, where an entire output channel group is completed for a given ifmap row before moving to the next row.

### 4.4 INNER_LOOP
The INNER_LOOP state implements the fine-grained advancement within one output channel group. It advances the m counter (filter group index) and the C counter (input channel index). The logic is:

1. Test if `m_crnt + (p * t) == m`. If true, the current filter group within this M slice is complete. Reset m_crnt to zero.
2. Then test if `C_crnt + (q * r) == C`. If true, all input channels have been processed for this group. Reset C_crnt to zero and transition to DUMPING.
3. If the C test fails, increment C_crnt by `q * r` and return to CHECK.
4. If the m test fails, increment m_crnt by `p * t` and return to CHECK.

The expressions `p * t` and `q * r` represent the granularity of one pass: `p * t` filter weights (p accumulators times t filter slices) and `q * r` input channels (q filter rows times r channels per array).

### 4.5 START_PASS
This state is a single-cycle pulse state. Upon entry, it asserts `start_noc = 1'b1` to trigger all four NoC channels (ifmap, filter, ipsum, opsum) to begin data delivery. The state unconditionally transitions to PROCESS on the next cycle. The `start_noc` signal is a combinational output derived from the current state, so it is asserted for exactly one clock cycle at the posedge where `state_crnt == START_PASS`.

### 4.6 PROCESS
The PROCESS state is the main execution state. It asserts `busy = 1'b1` to indicate that the PE array is actively computing. It remains in this state until the external `noc_done` signal is asserted, which indicates that all four NoC channels have completed their data delivery for this pass. Upon `noc_done`, the FSM transitions to PASS_DONE.

### 4.7 PASS_DONE
A single-cycle state that asserts `pass_done = 1'b1` on the combinational output. This signals to the external system (and to the aggregator / data collection logic) that one pass of computation has completed. The FSM unconditionally transitions to INNER_LOOP, which will either advance counters and start another pass, or trigger a dump if input channels are exhausted.

### 4.8 DUMPING
The DUMPING state handles the readout of accumulated partial sums from the PE array to global buffers. It asserts `ofmap_dump = 1'b1` and waits for the external `dump_done` signal. When `dump_done` is asserted, the FSM transitions to OUTER_LOOP, which advances the outer loop counters and may start a new pass group or terminate. The output feature map (ofmap) data is collected when all input channels (C) for a given output channel group have been processed, because the PE accumulators hold the complete partial sums at that point.

### 4.9 DONE
A single-cycle terminal state. It asserts `done = 1'b1` and unconditionally transitions back to IDLE. The `done` signal indicates that the full convolution has been completed.

## 5. ID Range Output Logic

The Scheduler produces three sets of ID range outputs that inform the NoC which slices of data to fetch from global buffers:

- **filter_ids[0:1]**: Two-element array giving the start (index 0) and end (index 1) filter weight indices for the current pass, formatted as `{M_crnt + m_crnt + 1, M_crnt + m_crnt + (p * t)}`. These are 1-indexed ranges (the +1 offset).
- **filter_channel_ids[0:1]** (shared with ifmap_channel_ids): The channel index range `{C_crnt + 1, C_crnt + (q * r)}`, representing the input channel slice for this pass.
- **ifmap_ids[0:1]**: The ifmap group range `{N_crnt + 1, N_crnt + n}`.
- **ifmap_channel_ids[0:1]** and **psum_ids[0:1]** and **psum_channel_ids[0:1]**: These are cross-wired -- filter_channel_ids and ifmap_channel_ids both connect to the same `channel_ids` wire, since input channels are shared between ifmap and filter access. psum_ids equals ifmap_ids, and psum_channel_ids equals filter_ids, reflecting the storage layout of partial sums.

The ID ranges are computed in a separate `always_comb` block with three branches:

1. **During IDLE or DONE**: All outputs are driven to zero, and `bias_sel` is deasserted.
2. **During DUMPING**: Filter IDs give the entire M-slice range `{M_crnt + 1, M_crnt + m}`, channel IDs give the full C range `{1, C}`, and ifmap IDs give the N-slice range `{N_crnt + 1, N_crnt + n}`. This provides the complete address range for dumping accumulated output.
3. **During all other states** (CHECK, OUTER_LOOP, INNER_LOOP, START_PASS, PROCESS, PASS_DONE): The ranges are the per-pass slices as described above. Additionally, `bias_sel` is asserted when `channel_ids[0] == 0`, meaning the very first pass for a new output channel group requires bias addition (the accumulator must be initialized with the bias value rather than accumulated from a previous partial sum).

## 6. Signal Timing and Handshake Protocol

The Scheduler's output signals follow a specific timing protocol:

- **start_noc**: Asserted for exactly one cycle in the START_PASS state. This triggers the pass_controller inside noc_wrapper, which launches all four NoC channels in parallel.
- **busy**: Asserted throughout the PROCESS state. It indicates the PE array is actively computing. Deasserted as soon as noc_done arrives.
- **noc_done** (input): Generated by the NoC controller when all four channels complete. The critical design rule is that `done = opsum_done` in noc_controller -- only the opsum channel's completion matters because it is always the last to finish (it must read back all PE partial sums).
- **pass_done**: Asserted for one cycle in PASS_DONE state. This signals the completion of one full pass to any downstream logic.
- **ofmap_dump**: Asserted for the duration of the DUMPING state. It triggers the output feature map collection.
- **done**: Asserted for one cycle when all convolution work is complete.

## 7. Parameter Flow: Scan Chain to Scheduler

The configuration parameters (E, C, M, N, m, n, e, p, q, r, t) arrive at the Scheduler as input ports. In the broader system, these parameters are loaded via a scan chain that runs through the PE array (enable bits, ipsum_ln_sel, opsum_ln_sel) and the NoC (GIN/GON MCC IDs). However, the Scheduler itself receives them as parallel inputs -- the scan chain loading is handled at a higher hierarchy level. The Scheduler uses these parameters combinatorially to compute loop bounds, counter increments, and ID ranges.

A critical derived quantity used elsewhere in the system (not inside the Scheduler) is `D = (e << (U >> 1)) + R - U`, computed in the NoC controller. This represents the total number of ifmap rows needed for the current convolution, accounting for stride (U) and filter height (R). The Scheduler does not use D directly; it is computed in noc_controller for address generation.

## 8. Combinational vs. Sequential Logic: Block-by-Block Description

### 8.1 The `always_ff` Sequential Block

This block (lines 65-81) implements the register update on `posedge clk or posedge reset`. On reset, all counters (C_crnt, M_crnt, N_crnt, m_crnt, E_crnt) are cleared to zero and the state returns to IDLE. On each clock edge without reset, the present-value registers are updated to their corresponding next-value signals. This is a standard synchronous register pattern.

### 8.2 The Main `always_comb` Block: Next-State and Output Logic

This block (lines 83-178) is the heart of the Scheduler. It first drives all output signals to default deasserted values. Then it drives all `_nxt` counters to their current values (the "no change" default). Finally, the `case(state_crnt)` statement overrides these defaults based on the current state and transition conditions.

The use of `case(state_crnt)` (the current state, not the next state) for output generation is by design: combinatorial outputs based on the current state produce glitch-free signals. The next-state logic determines where the FSM will go on the next posedge.

Each state's logic was described in Section 4 above. The key pattern is: default to "no change," then override when conditions are met. This default-assignment style prevents unintended latch inference and makes the behavior of unhandled conditions explicit.

### 8.3 The ID Range `always_comb` Block

This block (lines 180-200) is a separate combinational process that computes the ID range outputs. It is separated from the main FSM combinational block for clarity. It reads `state_crnt`, `M_crnt`, `m_crnt`, `C_crnt`, `N_crnt`, and the parameters `n`, `p`, `t`, `q`, `r`, `C` to produce the three output arrays.

The separation into its own block also highlights the protocol: the ID ranges are valid during all active states (CHECK through PASS_DONE) and invalid (driven to zero) during IDLE and DONE.

### 8.4 The Continuous Assign Statements

Three continuous assignments wire the shared channel ID array:
```
assign filter_channel_ids = channel_ids;
assign ifmap_channel_ids = channel_ids;
assign psum_ids = ifmap_ids;
assign psum_channel_ids = filter_ids;
```

This reflects the architectural fact that ifmap and filter data share the same input channel indexing, and partial sums are organized by ifmap group and filter group in global buffers.

## 9. Loop Nest Analysis

The convolution loop nest implemented by the Scheduler has the following structure (outer to inner):

1. **N loop** (ifmap groups): Iterates from 0 to N-1 in steps of `n`
2. **E loop** (ifmap rows): Iterates from 0 to E-1 in steps of `e`
3. **M loop** (output channels): Iterates from 0 to M-1 in steps of `m`
4. **C loop** (input channels): Iterates from 0 to C-1 in steps of `q * r`
5. **m loop** (filter sub-groups): Iterates from 0 to m-1 in steps of `p * t`

The m loop is implemented in the INNER_LOOP state; the M, E, N loops are implemented in OUTER_LOOP; the C loop is folded into INNER_LOOP alongside m.

The total number of passes executed is: (N/n) * (E/e) * (M/m) * (C/(q*r)) * (m/(p*t)).

Each pass corresponds to one START_PASS -> PROCESS -> PASS_DONE -> INNER_LOOP cycle, during which the NoC delivers data and the PE array computes partial sums for one slice of the convolution.

## 10. The Critical Role of start_pass

The `start_pass` input and CHECK state deserve special attention. The system is designed so that the Scheduler pauses at the CHECK state after every outer-loop or inner-loop counter advancement. It waits for an external `start_pass` signal before proceeding to START_PASS.

This handshake serves several purposes:
- It allows the external control logic to buffer data in global BRAMs before launching a NoC transaction.
- It provides a clean synchronization point for the testbench to verify intermediate states.
- It decouples the control flow pacing from the internal state machine timing.

In a fully autonomous system, `start_pass` would be tied to a signal indicating that global buffer data is ready. The CHECK state is the architectural hook for this readiness check.



**调度器模块：寄存器传输级描述**

**1. 模块概述与架构角色**

调度器是 Eyeriss 加速器的顶层控制单元。它通过排定数据移动（NoC 事务）、处理单元（PE）执行以及跨多个处理趟的部分和累积的顺序，来编排整个卷积计算。调度器作为一个具有九个状态的分层有限状态机（FSM）运行，控制着两个嵌套的循环层级：一个外层循环，遍历输出通道组（M）、ifmap 行（E）和 ifmap 组（N）；以及一个内层循环，遍历细粒度的滤波器组（m）和输入通道组（C）。内层循环的每次迭代触发一个“处理趟”——这是 NoC 将数据传递给 PE 阵列、PE 计算一轮乘加操作的工作单元。

该模块从扫描链接收配置参数，并产生标识符（ID）范围输出，告诉 NoC 从全局缓冲区中取哪些滤波器、ifmap 和部分和张量的切片。它还发出控制握手信号（`start_noc`、`busy`、`done`、`pass_done`、`ofmap_dump`），用于协调整个系统。

**2. 参数化**

调度器通过所有配置和计数器寄存器的宽度参数进行参数化。关键参数包括：

-   **E_WIDTH（6 位）**：ifmap 行计数 E 的宽度，定义了 ifmap 的最大行数。
-   **C_WIDTH（10 位）**：输入通道计数 C 的宽度。
-   **M_WIDTH（10 位）**：输出通道计数 M 的宽度。
-   **N_WIDTH（3 位）**：ifmap 组计数 N 的宽度。
-   **m_WIDTH（6 位）**、**n_WIDTH（3 位）**、**e_WIDTH（6 位）**：细粒度循环边界的宽度（m：一个处理趟内的滤波器组，n：ifmap 组，e：一个组内的 ifmap 行）。
-   **p_WIDTH（5 位）**、**q_WIDTH（3 位）**、**r_WIDTH（2 位）**、**t_WIDTH（3 位）**：PE 阵列维度和分块因子的宽度（p：每个 PE 的累积器数，q：滤波器行，r：每个阵列的滤波器通道数，t：每个阵列的滤波器切片数）。

这些宽度从顶层设计传播而来，并决定了所有内部计数器和 ID 范围输出的位宽。

**3. 寄存器文件和状态编码**

调度器维护五个内部计数器寄存器和一个状态寄存器，每个都有当前值（`_crnt`）和下一个值（`_nxt`）变体：

-   **C_crnt / C_nxt**：此处理趟组的当前输入通道基址偏移。它跟踪正在处理 C 输入通道的哪一片。在内层循环完成时递增 `q * r`。
-   **M_crnt / M_nxt**：当前输出通道基址偏移。它跟踪正在处理 M 输出通道的哪一片。在外层循环完成时递增 `m`。
-   **N_crnt / N_nxt**：当前 ifmap 组基址偏移。它跟踪正在处理哪组 N 个 ifmap。递增 `n`。
-   **E_crnt / E_nxt**：当前 ifmap 行基址偏移。它跟踪 ifmap 内在处理哪一行，以 `e` 为增量。
-   **m_crnt / m_nxt**：一个输出通道趟内的细粒度滤波器组计数器。在每个处理趟递增 `p * t`。

状态寄存器 `state_crnt` 是枚举类型 `state_type`，具有九个值：`IDLE`、`CHECK`、`OUTER_LOOP`、`INNER_LOOP`、`START_PASS`、`PROCESS`、`PASS_DONE`、`DUMPING` 和 `DONE`。

所有寄存器在 `clk` 的正沿更新，或在 `reset` 的正沿异步复位为零/IDLE。这在一个单独的 `always_ff` 块中实现。下一个状态值（`state_nxt` 和所有 `_nxt` 计数器）在一个单独的 `always_comb` 块中计算，确保无毛刺的转换。

**4. 九状态 FSM：逐状态描述**

**4.1 IDLE**
调度器从 IDLE 开始。所有输出（`start_noc`、`pass_done`、`busy`、`done`、`ofmap_dump`）被驱动为零。下一个状态逻辑仅检查外部 `start` 信号：当 `start` 被断言时，FSM 转换到 CHECK。没有计数器被修改。

**4.2 CHECK**
CHECK 状态是在每个处理趟和每次外循环迭代之间插入的一个同步点。它的唯一目的是在继续之前等待外部 `start_pass` 信号。此握手允许外部系统（或测试台）门控每个处理趟的启动，例如，确保全局缓冲区数据就绪或之前的流水线操作已排空。当 `start_pass` 被断言时，FSM 转换到 START_PASS。没有计数器被修改。

**4.3 OUTER_LOOP**
OUTER_LOOP 状态实现卷积循环嵌套的最外层三个层级：遍历输出通道（M）、ifmap 行（E）和 ifmap 组（N）。推进逻辑是一系列溢出检查：

1.  首先，状态测试 `M_crnt + m == M`。如果此条件成立，当前的 M 组已达到总输出通道计数。在此情况下，M_crnt 被复位为零，状态继续测试 E。
2.  然后测试 `E_crnt + e >= E`（注意：大于等于，不仅仅是等于）。如果此条件成立，E_crnt 被复位为零，状态继续测试 N。
3.  然后测试 `N_crnt + n == N`。如果此条件成立，N_crnt 被复位为零，FSM 转换到 DONE（所有卷积工作完成）。
4.  如果 E 测试失败，E_crnt 递增 `e`，FSM 返回 CHECK。
5.  如果顶层的 M 测试失败，M_crnt 递增 `m`，FSM 返回 CHECK。
6.  如果 N 测试通过，但 M 或 E 不在其极限值，N_crnt 递增 `n`，FSM 返回 CHECK。

关键的洞察是，M 在 E 之前循环，E 在 N 之前循环，建立了从最内层（M）到最外层（N）的循环嵌套：M 变化最快，然后是 E，最后是 N。这与行平稳架构所需的数据流顺序相匹配，在这种顺序中，在为给定 ifmap 行移动到下一行之前，要完成一个完整的输出通道组。

**4.4 INNER_LOOP**
INNER_LOOP 状态实现一个输出通道组内的细粒度推进。它推进 m 计数器（滤波器组索引）和 C 计数器（输入通道索引）。逻辑是：

1.  测试 `m_crnt + (p * t) == m`。如果为真，则此 M 切片内的当前滤波器组已完成。将 m_crnt 复位为零。
2.  然后测试 `C_crnt + (q * r) == C`。如果为真，则此组的所有输入通道均已处理完毕。将 C_crnt 复位为零并转换到 DUMPING。
3.  如果 C 测试失败，将 C_crnt 递增 `q * r` 并返回 CHECK。
4.  如果 m 测试失败，将 m_crnt 递增 `p * t` 并返回 CHECK。

表达式 `p * t` 和 `q * r` 代表一个处理趟的粒度：`p * t` 个滤波器权重（p 个累积器乘以 t 个滤波器切片）和 `q * r` 个输入通道（q 个滤波器行乘以 r 个每阵列通道数）。

**4.5 START_PASS**
此状态是一个单周期脉冲状态。进入时，它断言 `start_noc = 1'b1` 以触发所有四个 NoC 通道（ifmap、filter、ipsum、opsum）开始数据传输。该状态在下一个周期无条件转换到 PROCESS。`start_noc` 信号是从当前状态导出的组合输出，因此它在 `state_crnt == START_PASS` 的 posedge 处被断言恰好一个时钟周期。

**4.6 PROCESS**
PROCESS 状态是主要的执行状态。它断言 `busy = 1'b1` 以指示 PE 阵列正在积极计算。它保持在此状态，直到外部 `noc_done` 信号被断言，这表明所有四个 NoC 通道已完成此处理趟的数据传输。一旦 `noc_done` 被断言，FSM 转换到 PASS_DONE。

**4.7 PASS_DONE**
一个单周期状态，在组合输出上断言 `pass_done = 1'b1`。这向外部系统（以及聚合器/数据收集逻辑）发出信号，表明一个处理趟的计算已完成。FSM 无条件转换到 INNER_LOOP，它将推进计数器并启动另一个处理趟，或者在输入通道耗尽时触发转储。

**4.8 DUMPING**
DUMPING 状态处理将累积的部分和从 PE 阵列读回到全局缓冲区。它断言 `ofmap_dump = 1'b1` 并等待外部 `dump_done` 信号。当 `dump_done` 被断言时，FSM 转换到 OUTER_LOOP，后者推进外循环计数器，并可能启动一个新的处理趟组或终止。输出特征图（ofmap）数据是在给定输出通道组的所有输入通道（C）都已处理完毕时收集的，因为那时 PE 累积器保存着完整的部分和。

**4.9 DONE**
一个单周期终止状态。它断言 `done = 1'b1` 并无条件转换回 IDLE。`done` 信号表示完整的卷积已经完成。

**5. ID 范围输出逻辑**

调度器产生三组 ID 范围输出，通知 NoC 从全局缓冲区取哪些数据切片：

-   **filter_ids[0:1]**：二元数组，给出当前处理趟的起始（索引 0）和结束（索引 1）滤波器权重索引，格式为 `{M_crnt + m_crnt + 1, M_crnt + m_crnt + (p * t)}`。这些是基于 1 的范围（+1 偏移量）。
-   **filter_channel_ids[0:1]**（与 ifmap_channel_ids 共享）：通道索引范围 `{C_crnt + 1, C_crnt + (q * r)}`，表示此处理趟的输入通道切片。
-   **ifmap_ids[0:1]**：ifmap 组范围 `{N_crnt + 1, N_crnt + n}`。
-   **ifmap_channel_ids[0:1]** 和 **psum_ids[0:1]** 以及 **psum_channel_ids[0:1]**：这些是交叉连接的——filter_channel_ids 和 ifmap_channel_ids 都连接到相同的 `channel_ids` 线，因为输入通道在 ifmap 和滤波器访问之间是共享的。psum_ids 等于 ifmap_ids，psum_channel_ids 等于 filter_ids，反映了部分和的存储布局。

ID 范围在一个单独的 `always_comb` 块中计算，该块有三个分支：

1.  **在 IDLE 或 DONE 期间**：所有输出被驱动为零，并且 `bias_sel` 被取消断言。
2.  **在 DUMPING 期间**：滤波器 ID 给出整个 M 切片范围 `{M_crnt + 1, M_crnt + m}`，通道 ID 给出完整的 C 范围 `{1, C}`，ifmap ID 给出 N 切片范围 `{N_crnt + 1, N_crnt + n}`。这为转储累积输出提供了完整的地址范围。
3.  **在所有其他状态期间**（CHECK、OUTER_LOOP、INNER_LOOP、START_PASS、PROCESS、PASS_DONE）：范围是如上所述的每个处理趟切片。此外，当 `channel_ids[0] == 0` 时，`bias_sel` 被断言，这意味着新的输出通道组的第一个处理趟需要偏置加法（累积器必须用偏置值初始化，而不是从先前的部分和累积）。

**6. 信号时序和握手协议**

调度器的输出信号遵循特定的时序协议：

-   **start_noc**：在 START_PASS 状态中恰好断言一个周期。这触发 noc_wrapper 内部的 pass_controller，后者并行启动所有四个 NoC 通道。
-   **busy**：在 PROCESS 状态期间被断言。它指示 PE 阵列正在积极计算。一旦 noc_done 到达，立即取消断言。
-   **noc_done（输入）**：当所有四个通道完成时，由 NoC 控制器产生。关键的设计规则是，在 noc_controller 中 `done = opsum_done`——只有 opsum 通道的完成是重要的，因为它总是最后完成（它必须读回所有 PE 部分和）。
-   **pass_done**：在 PASS_DONE 状态中恰好断言一个周期。这向下游的任何逻辑发信号表明一个完整的处理趟已完成。
-   **ofmap_dump**：在 DUMPING 状态的持续时间内被断言。它触发输出特征图收集。
-   **done**：当所有卷积工作完成时，恰好断言一个周期。

**7. 参数流：扫描链到调度器**

配置参数（E、C、M、N、m、n、e、p、q、r、t）作为输入端口到达调度器。在更广泛的系统中，这些参数通过扫描链加载，该扫描链贯穿 PE 阵列（使能位、ipsum_ln_sel、opsum_ln_sel）和 NoC（GIN/GON MCC ID）。然而，调度器本身将它们作为并行输入接收——扫描链加载在更高的层级处理。调度器组合地使用这些参数来计算循环边界、计数器增量和 ID 范围。

在系统的其他地方（而非调度器内部）使用的一个关键导出量是 `D = (e << (U >> 1)) + R - U`，在 NoC 控制器中计算。这表示当前卷积所需的 ifmap 总行数，考虑了步长（U）和滤波器高度（R）。调度器不直接使用 D；它在 noc_controller 中为地址生成而计算。

**8. 组合逻辑与时序逻辑：逐块描述**

**8.1 `always_ff` 时序块**

此块（第 65-81 行）在 `posedge clk or posedge reset` 上实现寄存器更新。在复位时，所有计数器（C_crnt、M_crnt、N_crnt、m_crnt、E_crnt）被清零，状态返回 IDLE。在没有复位的每个时钟沿，当前值寄存器被更新为其对应的下一个值信号。这是一个标准的同步寄存器模式。

**8.2 主 `always_comb` 块：下一个状态和输出逻辑**

此块（第 83-178 行）是调度器的核心。它首先将所有输出信号驱动为默认的取消断言值。然后，它将所有 `_nxt` 计数器驱动为其当前值（“无变化”默认值）。最后，`case(state_crnt)` 语句基于当前状态和转换条件覆盖这些默认值。

使用 `case(state_crnt)`（当前状态，而非下一个状态）进行输出生成是特意设计的：基于当前状态的组合输出产生无毛刺信号。下一个状态逻辑决定 FSM 将在下一个 posedge 转到哪里。

每个状态的逻辑已在上述第 4 节中描述。关键模式是：默认为“无变化”，然后在满足条件时覆盖。这种默认赋值风格可防止意外的锁存器推断，并使未处理条件的行为显式化。

**8.3 ID 范围 `always_comb` 块**

此块（第 180-200 行）是一个单独的组合过程，用于计算 ID 范围输出。为清晰起见，它与主 FSM 组合块分开。它读取 `state_crnt`、`M_crnt`、`m_crnt`、`C_crnt`、`N_crnt` 以及参数 `n`、`p`、`t`、`q`、`r`、`C` 以产生三个输出数组。

将其分离到自己的块中也突出了协议：ID 范围在所有活跃状态（CHECK 到 PASS_DONE）期间是有效的，在 IDLE 和 DONE 期间是无效的（驱动为零）。

**8.4 连续赋值语句**

三个连续赋值连接共享的通道 ID 数组：
```
assign filter_channel_ids = channel_ids;
assign ifmap_channel_ids = channel_ids;
assign psum_ids = ifmap_ids;
assign psum_channel_ids = filter_ids;
```
这反映了架构事实，即 ifmap 和滤波器数据共享相同的输入通道索引，并且部分和在全局缓冲区中按 ifmap 组和滤波器组组织。

**9. 循环嵌套分析**

由调度器实现的卷积循环嵌套具有以下结构（从外到内）：

1.  **N 循环**（ifmap 组）：以 `n` 为步长从 0 迭代到 N-1
2.  **E 循环**（ifmap 行）：以 `e` 为步长从 0 迭代到 E-1
3.  **M 循环**（输出通道）：以 `m` 为步长从 0 迭代到 M-1
4.  **C 循环**（输入通道）：以 `q * r` 为步长从 0 迭代到 C-1
5.  **m 循环**（滤波器子组）：以 `p * t` 为步长从 0 迭代到 m-1

m 循环在 INNER_LOOP 状态中实现；M、E、N 循环在 OUTER_LOOP 中实现；C 循环与 m 一起被折叠到 INNER_LOOP 中。

执行的处理趟总数是：(N/n) * (E/e) * (M/m) * (C/(q*r)) * (m/(p*t))。

每个处理趟对应一个 START_PASS -> PROCESS -> PASS_DONE -> INNER_LOOP 周期，在此期间 NoC 传递数据，PE 阵列为卷积的一个切片计算部分和。

**10. start_pass 的关键角色**

`start_pass` 输入和 CHECK 状态值得特别关注。系统的设计使得调度器在每次外循环或内循环计数器推进后，在 CHECK 状态暂停。它在继续到 START_PASS 之前等待外部 `start_pass` 信号。

此握手有几个目的：
-   它允许外部控制逻辑在启动 NoC 事务之前在全局 BRAM 中缓冲数据。
-   它为测试台验证中间状态提供了一个干净的同步点。
-   它将控制流节奏与内部状态机时序解耦。

在一个完全自主的系统中，`start_pass` 将被连接到一个指示全局缓冲区数据就绪的信号。CHECK 状态是此就绪检查的架构钩子。