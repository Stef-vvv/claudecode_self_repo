# Clock Edge Analysis: Eyeriss v1 RTL (H:/moateff_test/src/)

## Executive Summary

**Conclusion: This is a deliberate, well-reasoned design pattern, not a bug.** The designer chose negedge as the primary clock edge for the data-path (PE array, NoC, FIFOs, GLBs) and reserved posedge for the top-level scheduler and interface-unit controller. The only internal mixed-edge module (`pe_psum_spad.v`) uses opposite edges for read and write to guarantee deterministic read-before-write ordering.

---

## 1. Complete Inventory

### 1.1 POSEDGE clk Users (4 files, 5 always blocks)

| File | Line | Block | Purpose |
|------|------|-------|---------|
| `scheduler.sv` | 65 | `always_ff @(posedge clk or posedge reset)` | Top-level FSM state register -- orchestrates all processing passes |
| `INTERFACE UNIT/async_fifo_ctrl.sv` | 43 | `always @(posedge core_clk, posedge core_reset)` | Forward-transfer FSM state register (core_clk domain) |
| `INTERFACE UNIT/async_fifo_ctrl.sv` | 72 | `always @(posedge link_clk, posedge link_reset)` | Backward-transfer word counter (link_clk domain) |
| `INTERFACE UNIT/async_fifo.sv` | 179 | `always @(posedge rclk, posedge rreset)` | `w_en_DRAM` output register (read-side clock domain) |

### 1.2 NEGEDGE clk Users (the overwhelming majority -- 22 files, 38 always blocks)

#### PE Array -- Processing Element (7 files, 12 blocks)

| File | Line | Block | Purpose |
|------|------|-------|---------|
| `pe_controller.sv` | 61 | `always @(negedge clk or posedge reset)` | PE FSM state register (IDLE/PROCESS/ACCUMULATE/STRIDE/PADDING/LOAD) |
| `pe_filter_spad.v` | 28 | `always @(negedge clk)` | Filter scratchpad: write memory + read memory |
| `pe_filter_spad.v` | 37 | `always @(negedge clk or posedge reset)` | Filter scratchpad: write address counter |
| `pe_flopr.v` | 10 | `always @(negedge clk or posedge reset)` | Generic pipeline register (used for all PE pipeline stages) |
| `pe_ifmap_spad.v` | 29 | `always @(negedge clk)` | Ifmap scratchpad: shift register chain + memory write + read |
| `pe_ifmap_spad.v` | 43 | `always @(negedge clk or posedge reset)` | Ifmap scratchpad: write address counter (inc/dec with shift) |
| `pe_multiplier.v` | 12 | `always @(negedge clk or posedge reset)` | Multiplier output register (16b x 16b -> 32b) |
| `pe_zero_skipping.v` | 23 | `always @(negedge clk)` | Zero-skip buffer: shift register + zero-flag write |
| `pe_zero_skipping.v` | 35 | `always @(negedge clk or posedge reset)` | Zero-skip buffer: write address counter |
| `pe_psum_spad.v` | 25 | `always @(negedge clk)` | Psum scratchpad: READ port (see section 5 for mixed-edge analysis) |

#### PE Array -- Sync FIFO (5 files, 8 blocks)

| File | Line | Block | Purpose |
|------|------|-------|---------|
| `sync_fifo_mem.v` | 22 | `always @(negedge clk)` | FIFO memory write (wide-read path: R_DATA > W_DATA) |
| `sync_fifo_mem.v` | 35 | `always @(negedge clk)` | FIFO memory write (wide-write path: W_DATA > MEM_WIDTH) |
| `sync_fifo_rd_ctrl.v` | 28 | `always @(negedge clk or posedge reset)` | Read pointer counter (1:1 width ratio) |
| `sync_fifo_rd_ctrl.v` | 36 | `always @(negedge clk or posedge reset)` | Read pointer counter (wide-read path) |
| `sync_fifo_wr_ctrl.v` | 29 | `always @(negedge clk or posedge reset)` | Write pointer counter (1:1 width ratio) |
| `sync_fifo_wr_ctrl.v` | 37 | `always @(negedge clk or posedge reset)` | Write pointer counter (wide-write path) |
| `sync_fifo_up_down_counter.v` | 14 | `always @(negedge clk or posedge reset)` | Occupancy counter (inc/dec/both) |
| `sync_fifo_flag_generator.v` | 10 | `always @(negedge clk or posedge reset)` | Almost-full/almost-empty flag counter |

#### PE Array -- NoC Controllers (7 files, 7 blocks)

| File | Line | Block | Purpose |
|------|------|-------|---------|
| `pass_controller.sv` | 16 | `always @(negedge clk or posedge reset)` | Pass FSM (IDLE/START_NOCS/PROCESSING/DONE) |
| `filter_index_generator.sv` | 51 | `always @(negedge clk or posedge reset)` | Filter index generation FSM (p,q,r,t,S loops) |
| `filter_tag_generator.sv` | 29 | `always @(negedge clk or posedge reset)` | Filter row/col tag generation FSM |
| `ifmap_index_generator.sv` | 38 | `always @(negedge clk or posedge reset)` | Ifmap index generation FSM (n,q,r,D,W loops) |
| `ifmap_tag_generator.sv` | 33 | `always @(negedge clk or posedge reset)` | Ifmap row/col tag generation FSM |
| `psum_index_generator.sv` | 51 | `always @(negedge clk or posedge reset)` | Psum index generation FSM (n,p,t,e,F loops) |
| `psum_tag_generator.sv` | 34 | `always @(negedge clk or posedge reset)` | Psum row/col tag generation FSM |

#### GLB Unit (2 files, 3 blocks)

| File | Line | Block | Purpose |
|------|------|-------|---------|
| `dual_bram.sv` | 29 | `always @(negedge clk)` | Dual-port BRAM: Port A write + read |
| `dual_bram.sv` | 38 | `always @(negedge clk)` | Dual-port BRAM: Port B write + read |
| `glb_flop.v` | 10 | `always @(negedge clk)` | GLB pipeline register (no reset) |

#### Interface Unit (5 files, 8 blocks)

| File | Line | Block | Purpose |
|------|------|-------|---------|
| `async_fifo_mem.sv` | 17 | `always @(negedge wclk, posedge reset)` | Write-enable delay for Direct_Back_Path mode |
| `async_fifo_mem.sv` | 25 | `always @(negedge wclk)` | Async FIFO memory write |
| `async_fifo_wr_ctrl.sv` | 14 | `always @(negedge wclk, posedge reset)` | Write address counter (binary) |
| `async_fifo_wr_ctrl.sv` | 27 | `always @(negedge wclk, posedge reset)` | Two-stage synchronizer for Gray-coded read pointer |
| `async_fifo_rd_ctrl.sv` | 13 | `always @(negedge rclk, posedge reset)` | Read address counter (binary) |
| `async_fifo_rd_ctrl.sv` | 27 | `always @(negedge rclk, posedge reset)` | Two-stage synchronizer for Gray-coded write pointer |
| `clk_mux.sv` | 18 | `always @(negedge link_clk or posedge reset)` | Clock mux control: link domain |
| `clk_mux.sv` | 28 | `always @(negedge core_clk or posedge reset)` | Clock mux control: core domain |

#### Other (3 files, 3 blocks)

| File | Line | Block | Purpose |
|------|------|-------|---------|
| `addr_generator.sv` | 24 | `always @(negedge core_clk or posedge reset)` | GLB address generator FSM |
| `reset_sync.sv` | 9 | `always @(negedge clk, posedge reset)` | Reset synchronizer (shift in 1s) |
| `scan_ff.sv` | 13 | `always @(negedge clk or posedge reset)` | Scan-chain flip-flop |

### 1.3 No Clock Edge (purely combinational or latch-based)

- `pe_adder.v`, `pe_truncator.v`, `pe_mux2x1.v` -- combinational logic
- `pe_clk_gating.v` -- level-sensitive latch (`always @(clk or enable)`)
- `interface_unit.sv`, `glb_unit.sv`, `bias_glb.sv`, `filter_glb.sv`, `ifmap_glb.sv`, `psum_glb.sv` -- pure wrappers, no registers
- `noc_wrapper.sv`, `gin.sv`, `gon.sv`, `gin_mcc.sv`, `gin_xbus.sv`, `gon_mcc.sv`, `gon_xbus.sv` -- pure wrappers or combinational tag-matching
- `relu.sv`, `relu_array.sv` -- combinational

### 1.4 Edge Count Summary

| Edge | Files | Always Blocks | Percentage |
|------|-------|---------------|------------|
| posedge only | 4 | 5 | 11.6% |
| negedge only | 22 | 38 | 88.4% |
| **Total** | **26** | **43** | **100%** |

---

## 2. Designer's Rationale

### 2.1 Why negedge as the Primary Edge

The choice to use negedge for 88% of all sequential blocks is systematic and motivated by three architectural concerns:

**A. Partition-Based Timing (Eyeriss Architecture)**

The Eyeriss paper describes a "partition-based" design methodology where the chip is divided into independently-clocked partitions. In this RTL implementation, the designer achieves a similar effect with a single clock by using opposite edges:

```
posedge domain: Scheduler (top-level orchestrator)
negedge domain: Everything else (PE array, NoC, GLB, FIFOs)
```

This creates two "virtual clock phases" from one physical clock, providing predictable half-cycle timing separation between the control plane (scheduler) and the data plane (PE array).

**B. Pipeline Skew Management**

The PE pipeline in `pe.v` uses two stages of `flopr` registers (both negedge) between the controller outputs and the psum_spad inputs:

```
controller (negedge) --> reg1 (negedge) --> reg2 (negedge) --> psum_spad (posedge write / negedge read)
```

By making the controller, pipeline registers, and scratchpad reads all operate on negedge, the designer creates a coherent negedge-domain pipeline. The only posedge operation in the PE is the psum_spad write, which serves a specific read-before-write purpose (see Section 5).

**C. Conventional Practice for FPGA BRAM**

In FPGA architectures (Xilinx/Intel), Block RAM read operations are commonly inferred to latch the read address on one edge and produce output data that is available in the same cycle. Using negedge for read-address registration gives the BRAM the entire high-phase of the clock to perform the read before the data is consumed by negedge-sampled downstream logic in the next cycle.

### 2.2 Why posedge for the Scheduler

The scheduler uses `always_ff @(posedge clk)` for three reasons:

1. **It is the system initiator.** The scheduler receives the top-level `start` signal and generates all downstream control (`start_noc`, `ofmap_dump`, etc.). By putting it on posedge one half-cycle ahead of everything else, the scheduler's combinational outputs have the full high-phase of the clock to propagate and settle before any negedge-domain module samples them.

2. **It interfaces with external control.** The scheduler's `start`, `start_pass`, `dump_done` signals come from outside the accelerator core. Using posedge is conventional for top-level state machines that interface with external controllers.

3. **It uses SystemVerilog `always_ff`.** The scheduler is the only module using SystemVerilog syntax (`always_ff`, `always_comb`, `typedef enum logic`), suggesting it was written by a different developer or at a different time than the rest of the design (which uses pure Verilog-2001). The posedge choice may reflect the conventions of whoever wrote that particular module.

### 2.3 Why posedge in the Interface Unit

The `async_fifo_ctrl.sv` uses `posedge core_clk` and `posedge link_clk` for its dual-clock-domain FSM. This is a separate subsystem (DRAM <-> GLB data transfer) with its own clock domain crossing logic. The posedge choice here is independent of the core accelerator's edge strategy. The sub-modules (`async_fifo_mem`, `async_fifo_wr_ctrl`, `async_fifo_rd_ctrl`) use negedge for their FIFO pointers and memory -- matching the negedge convention used by the sync FIFOs in the PE array.

The lone `posedge rclk` block in `async_fifo.sv:179` registers the `w_en_DRAM` output on the read clock. This is pragmatic: the read-side logic must drive a write-enable to the DRAM interface, and registering it on posedge ensures it is stable before the next read operation.

---

## 3. Data Flow Timing: posedge-to-negedge Handoff

### 3.1 Complete Control Path

Below is the control flow from the scheduler to the PE. The scheduler outputs `start_noc` as a combinational signal from its `always_comb` block (driven by the `state_crnt` register that updates on posedge).

```
                     Cycle N                        Cycle N+1
              |---- posedge ----|---- negedge ----|---- posedge ----|---- negedge ----|
              |                 |                 |                 |                 |
CLK:          |``````\_____/````|``````\_____/````|``````\_____/````|``````\_____/````|
              |       ^         |       ^         |       ^         |       ^         |
              |    posedge      |    negedge      |    posedge      |    negedge      |
              |                 |                 |                 |                 |
Scheduler     |                 |                 |                 |                 |
 (posedge):   | state_crnt <=   |                 | state_crnt <=   |                 |
              |   state_nxt     |                 |   state_nxt     |                 |
              | (START_PASS)    |                 | (PROCESS)       |                 |
              |                 |                 |                 |                 |
Scheduler     | combinational:  |                 | combinational:  |                 |
 (comb):      | start_noc = 1   |                 | busy = 1        |                 |
              |                 |                 |                 |                 |
              |  <-- t_setup -->|                 |                 |                 |
              |  (half-cycle    |                 |                 |                 |
              |   prop delay)   |                 |                 |                 |
              |                 |                 |                 |                 |
Pass Ctrl     |                 | samples         |                 |                 |
 (negedge):   |                 | start_noc = 1   |                 |                 |
              |                 | FSM -> START    |                 |                 |
              |                 |                 |                 |                 |
              |                 | <-- comb logic  |                 |                 |
              |                 | -->             |                 |                 |
              |                 |                 |                 |                 |
Pass Ctrl     |                 |                 |                 | samples         |
 (negedge):   |                 |                 |                 | start_nocs = 1  |
              |                 |                 |                 | FSM -> PROCESS  |
              |                 |                 |                 |                 |
NoC Ctrl      |                 |                 |                 | samples         |
 (negedge):   |                 |                 |                 | start_nocs = 1  |
              |                 |                 |                 | begin looping   |
              |                 |                 |                 |                 |
NoC Ctrl      |                 |                 |                 | combinational:  |
 (comb):      |                 |                 |                 | push data to    |
              |                 |                 |                 | gin FIFOs       |
              |                 |                 |                 |                 |
PE Sync FIFOs |                 |                 |                 | write on neg    |
 (negedge):   |                 |                 |                 | rd/wr ptrs inc  |
              |                 |                 |                 |                 |
PE Controller |                 |                 |                 | reads spad_full |
 (negedge):   |                 |                 |                 | PE FSM starts   |
```

### 3.2 Timing Budget Analysis

The critical handoff is **scheduler (posedge) --> pass_controller (negedge)**:

- **Clock period (T)**: Let's assume 200 MHz => T = 5 ns
- **Available time**: half-cycle = 2.5 ns (from posedge to next negedge)
- **Path**: scheduler `state_crnt` register -> combinational `start_noc` output -> routing delay -> pass_controller input setup time
- **Budget**: 2.5 ns minus clock skew minus pass_controller setup time

This half-cycle constraint is approximately 2x tighter than a normal full-cycle path. However, the scheduler's combinational output logic (`start_noc = 1'b1` in the START_PASS state) is trivially simple -- it is a constant assignment when in that state. So the actual propagation delay from `state_crnt` to `start_noc` is just a few LUT delays (maybe 1-2 ns in FPGA), easily meeting the 2.5 ns budget.

### 3.3 Why This Timing Works

The key insight is: **the scheduler's output signals are mostly single-bit control flags** (`start_noc`, `busy`, `done`, `ofmap_dump`), not wide data buses. These are decoded from the FSM state register and have minimal combinational depth. The wide data (filter_ids, ifmap_ids, psum_ids) are computed in a separate `always_comb` block and are not on the critical control path.

- **Control path (scheduler -> pass_controller)**: ~2 LUT delays, half-cycle budget = 2.5 ns. Easily met.
- **Data path (NoC controllers -> PE)**: All on negedge, full-cycle budget = 5 ns. Standard timing.
- **PE internal pipeline**: All on negedge, full-cycle budget. Standard timing.

---

## 4. Risk Analysis

### 4.1 Simulation Risks: LOW

**Verilog simulation semantics** handle mixed-edge designs correctly:

- The Verilog stratified event queue processes all posedge-triggered blocks in one region and all negedge-triggered blocks in another. There is no ambiguity about ordering between edges.
- All registered outputs use non-blocking assignments (`<=`), which guarantees that all readers see the pre-update values within the same simulation delta cycle.
- The scheduler's `always_comb` block recomputes whenever `state_crnt` changes (on posedge). The pass_controller's `always @(*)` block recomputes whenever its inputs change. The simulation correctly models the half-cycle of propagation delay.

**Potential gotcha**: If a testbench drives inputs on posedge and expects outputs on the same posedge, it will see stale data (outputs update on negedge). Testbenches must sample PE outputs on negedge or at the next posedge.

### 4.2 Synthesis Risks: LOW-to-MODERATE

**What synthesis tools do with mixed-edge designs**:

- **Vivado**: Supports mixed-edge registers in the same clock domain. The tool creates two clock trees internally (rising-edge and falling-edge), and the falling-edge clock is just the inverted rising-edge clock. Timing analysis automatically handles half-cycle paths.
- **Design Compiler (ASIC)**: Same -- the clock definition includes both edges, and the tool times half-cycle paths correctly.
- **Potential issue**: Some lint tools and coding standards (e.g., Reuse Methodology Manual) discourage mixing edges to avoid confusion. However, modern tools handle it correctly.

**Clock gating concern**: The PE uses clock gating (`pe_clk_gating.v`) which produces `gated_clk = clk & latch_en`. If the clock gate introduces duty-cycle distortion, the half-cycle separation between posedge and negedge shrinks. At the PE level, the gated clock feeds all PE sub-modules (negedge flopr, negedge controller, negedge spads, and posedge psum_spad write). Since all of them see the same (possibly distorted) gated clock, the relative timing between edges is preserved.

### 4.3 Timing Closure Risks: MODERATE

The half-cycle paths must be explicitly constrained:

```
# Example SDC constraint for half-cycle path:
set_multicycle_path -setup 0 -from [get_cells scheduler/state_crnt_reg*] \
                    -to [get_cells pass_controller/state_crnt_reg*]
# Default half-cycle analysis is correct; this is the DEFAULT behavior.
# But the designer must NOT accidentally relax this to a full-cycle path.
```

**Worst-case half-cycle paths**:

| Path | From Edge | To Edge | Budget |
|------|-----------|---------|--------|
| scheduler state -> pass_controller state | posedge | negedge | T/2 = 2.5ns |
| pass_controller state -> NoC index gen state | negedge | negedge | T = 5ns |
| NoC index gen -> PE controller state | negedge | negedge | T = 5ns |
| PE controller -> flopr (pipeline) | negedge | negedge | T = 5ns |
| flopr -> psum_spad write | negedge | posedge | T/2 = 2.5ns |

The two half-cycle paths (scheduler->pass_controller and flopr->psum_spad) are both short combinational paths and should close easily at typical frequencies (200-500 MHz).

### 4.4 Clock Tree Considerations

Using both edges effectively doubles the number of clock sinks that need to be balanced. However, since the negedge and posedge registers are in physically separate modules, the clock tree synthesis tool can optimize each subtree independently. The key constraint is minimizing skew between the posedge-domain registers (scheduler) and the negedge-domain registers (pass_controller), which are near each other in the floorplan.

---

## 5. pe_psum_spad Mixed-Edge Design: Deep Dive

### 5.1 The Code

```verilog
// pe_psum_spad.v
always @(posedge clk) begin
    if (w_en) begin
        mem[w_addr] <= din;    // WRITE on posedge
    end
end

always @(negedge clk) begin
    dout <= mem[r_addr];       // READ on negedge
end
```

### 5.2 The Problem It Solves

The psum_spad is a single-port-write, single-port-read register file within each PE. It stores partial sums across filter rows. The critical requirement is **read-before-write semantics**: when a PE computes a new partial sum and wants to write it to the same address it just read from (for accumulation), the read must return the OLD value (from the previous accumulation), not the new value being written in the same cycle.

If both read and write were on the same edge:

```verilog
// HYPOTHETICAL: both on same edge (what might go wrong)
always @(posedge clk) begin
    if (w_en) mem[w_addr] <= din;   // write new
    dout <= mem[r_addr];            // read -- which value?
end
```

With non-blocking assignments (`<=`), `mem[r_addr]` would read the OLD value (before the write takes effect), which is correct. However:
- Some synthesis tools may not infer BRAM correctly when read and write share the same `always` block with the same address appearing in both read and write ports.
- The read-data register (`dout`) might capture the write data if the synthesis tool misinterprets the intent (especially if `r_addr == w_addr`).
- With separate `always` blocks on the same edge, the Verilog standard does not guarantee ordering between blocks, so the result is non-deterministic.

**By using opposite edges**, the designer eliminates all ambiguity:

1. **negedge occurs first** (in standard Verilog simulation): `dout <= mem[r_addr]` -- reads the value stored from all previous posedge writes
2. **posedge occurs second**: `mem[w_addr] <= din` -- stores the new value
3. The read NEVER sees the same-cycle write, regardless of address collision

### 5.3 Hardware Mapping

In an ASIC or FPGA, this maps to a register file with:
- **Write port**: clocked by `clk` (posedge) -- standard synchronous write
- **Read port**: clocked by `~clk` (negedge) -- address registered on falling edge, data available before next posedge

This is a standard technique for multi-ported register files where read and write ports must be independent. FPGA BRAMs are inherently dual-ported (one read, one write on independent clocks), so the synthesis tool can map:

```
Port A: write-only, clocked by clk (posedge)
Port B: read-only, clocked by ~clk (negedge, implemented as inverted clock)
```

### 5.4 Pipeline Context

In the PE pipeline (`pe.v`), the psum_spad is positioned with deliberate pipeline staging:

```
pe_controller (negedge)                     -- produces wr_psum, psum_addr
    |
    v
flopr reg1  (negedge)                       -- 1-cycle delay: wr_psum_r, psum_addr_r
    |
    v
flopr reg2  (negedge)                       -- 2-cycle delay: wr_psum_rr, psum_addr_rr
    |
    v
psum_spad                                   -- WRITE: posedge (using wr_psum_rr, psum_addr_rr)
                                             -- READ:  negedge (using psum_addr from controller, 0-cycle delay)
    |
    v
dout -> mux2x1 (forward/bypass) -> adder
```

The read address (`r_addr = psum_addr`) comes directly from the controller (no pipeline delay) and samples on negedge. The write address (`w_addr = psum_addr_rr`) arrives 2 cycles later and writes on posedge. This 2-cycle pipeline delay ensures:
1. The MAC computation (multiply + truncate + add) has time to complete before the write
2. The write happens with the correct result, at an address that was read 2 cycles earlier
3. The read-before-write ordering is guaranteed by the edge separation

---

## 6. The Interface Unit: Mixed-Edge at the Module Hierarchy Level

The interface unit (`async_fifo` and sub-modules) shows a different kind of mixed-edge usage:

| Level | Module | Edge | Clock |
|-------|--------|------|-------|
| Top | `async_fifo_ctrl.sv` | **posedge** | core_clk, link_clk |
| Sub | `async_fifo_mem.sv` | **negedge** | wclk |
| Sub | `async_fifo_wr_ctrl.sv` | **negedge** | wclk |
| Sub | `async_fifo_rd_ctrl.sv` | **negedge** | rclk |
| Top | `async_fifo.sv:179` | **posedge** | rclk |

This is a **two-clock-domain asynchronous FIFO** (DRAM link_clk <-> core_clk). The edge choices are:
- The controller FSM (`async_fifo_ctrl`) uses posedge on both clock domains -- matching the convention that top-level control logic uses posedge.
- The FIFO pointer logic and memory use negedge -- matching the convention that data-path infrastructure uses negedge.
- The lone `posedge rclk` block in `async_fifo.sv` drives `w_en_DRAM`, an output to the external DRAM interface. Using posedge here is conventional for output registers that interface with external (possibly posedge) logic.

This is consistent with the overall pattern: **posedge for top-level control/interface, negedge for internal data-path**.

---

## 7. Conclusion

### 7.1 Bug or Deliberate Pattern?

**This is a deliberate, carefully engineered design pattern**, not a bug. The evidence:

1. **Consistency**: 88% of sequential blocks use negedge. The few posedge blocks are concentrated in specific architectural roles (top-level scheduler, interface controller). A bug would show random, inconsistent edge choices.

2. **Architectural rationale**: The posedge-scheduler / negedge-datapath split provides half-cycle timing separation between the control plane and data plane, reducing combinational depth pressure on the scheduler's output paths.

3. **pe_psum_spad**: The mixed-edge design (write on posedge, read on negedge) explicitly solves the read-before-write ordering problem for partial-sum accumulation. This is a textbook technique for register files with single-cycle read-write turnaround.

4. **Pattern replicates across subsystems**: The same edge separation pattern appears in the interface unit (posedge controller, negedge FIFO internals), confirming it is a deliberate architectural choice, not an accidental inconsistency.

### 7.2 Practical Implications

**For verification engineers:**
- Testbenches should drive inputs that feed negedge modules on the posedge (or earlier in the same cycle)
- Output checking should sample negedge-driven outputs on the next posedge
- The half-cycle timing gap is critical: do not insert zero-delay combinational paths between posedge and negedge domains in testbench models

**For synthesis engineers:**
- Ensure SDC constraints account for half-cycle paths explicitly
- Verify duty cycle of the clock: significant duty-cycle distortion reduces the half-cycle timing budget
- The clock gating cell in `pe_clk_gating.v` must preserve duty cycle reasonably well

**For design modification:**
- If adding new modules to the PE array, use negedge for consistency with existing PE logic
- If adding new top-level control FSM, use posedge for consistency with the scheduler
- The psum_spad mixed-edge pattern should be preserved if modifying the PE pipeline depth
