# Eyeriss V1 Author Evolution Trace

Following the author's chronological development across 4 sub-projects, from C models to final full system RTL.

---

## Project 1 (2025_7_18): C Data Delivery Patterns

### Files

| File | Lines | Purpose |
|------|-------|---------|
| `src/run.c` | 209 | Main: reads params, calls scheduler, orchestrates index generators |
| `src/Scheduler.c` | 36 | Scheduling loop: partitions M/C/N into passes |
| `src/Array.c` | 50 | 4D contiguous memory allocator and address calculator |
| `src/ifmap_index_generator.c` | 37 | Ifmap address sequence generator |
| `src/filter_index_generator.c` | 72 | Filter address sequence generator |
| `src/psum_index_generator.c` | 72 | Psum address sequence generator |
| `src/parameter.txt` | 14 | Test parameters (M=8, C=6, N=1, W=H=5, R=S=3, E=F=2, n=1, p=4, q=3, r=2, t=2) |

All 7 files are .c/.txt. No RTL. No building infrastructure (no Makefile).

### Scheduler Architecture

The scheduler (`Scheduler.c`) implements a **3-level nested loop**:

```
for N_ind in 0..N step n:
  for C_ind in 0..C step (q*r):
    for M_ind in 0..M step (p*t):
      emit: pass {filter_start..filter_end, channel_start..channel_end, ifmap_start..ifmap_end}
```

Each "processing pass" defines a rectangular chunk: M-range = `p*t` filters, C-range = `q*r` channels, N-range = `n` ifmaps. These ranges define what data gets loaded into GIN FIFOs and processed by the PE array in one pass.

**Key numbers**:
- `p*t` = number of filters processed in one pass (p=PE sets per filter, t=PE filter sets → p*t = 8 filters/row)
- `q*r` = number of channels processed (q=channels/PE_set, r=PE channel sets → q*r = 6 channels)
- `n` = number of ifmaps processed

### Index Generators (3 types)

All three produce cycle-by-cycle `{index, channel, row, col, address}` tuples written to text files.

**Ifmap index generator** -- 5 nested loops:
```
for n_ind in 0..n-1:
  for W_ind in 0..W-1:
    for q_ind in 0..q-1:
      for H_ind in 0..H-1:
        for r_ind in 0..r-1:
          emit: ifmap=n_ind, channel=q_ind+r_ind*q, row=H_ind, col=W_ind
```

**Filter index generator** -- uses a "register/lock" pattern with an inner loop of 4:
```
while (!lock_done):
  save current p/q/S as regs
  for R_ind in 0..R-1:
    for r_ind in 0..r-1:
      for t_ind in 0..t-1:
        for i in 0..3:    // 4 elements per inner cycle
          emit: filter=filter_start + p_ind + t_ind*p, channel=channel_start + q_ind + r_ind*q, row=R_ind, col=S_ind
          cascade-increment: p++ -> q++ -> S++
  restore p/q/S from regs
  // outer loops iterate
```
The `i` loop (4 iterations) corresponds to packing 4 16-bit filter values into a 64-bit data word for the GIN bus. The "register" mechanism saves/restores the inner indices between outer (R, r, t) loop iterations.

**Psum index generator** -- same register/lock pattern as filter but with indices n/p/F:
```
emit: psum=n_ind, channel=m + p_ind + t_ind*p, row=E_ind, col=F_ind
cascade-increment: p++ -> F++ -> n++
```

At DONE, updates `m` counter: `m += p*t` (move to next filter block).

### Correctness Assessment

- The C code compiles as a single source file (run.c #includes all others)
- **Bug: Only ONE pass is processed.** In `run.c` line 141, there is a `break;` statement inside the while loop that reads `scheduler.txt`. This means only the first processing pass is expanded, then the program terminates.
- The address calculator (`calculateAddress`) computes pointer difference, not an absolute address -- it returns an element offset rather than a byte address. No actual data values are used; the arrays are allocated but never filled.
- The filter/psum generators use `static int cycle_count` -- not thread-safe, but since it's a single-threaded C program, this is harmless.
- The parameter values favor small test: M=8, C=6, N=1, W=H=5, R=S=3, E=F=2.

### How to Compile and Run

```bash
cd H:/complete_version/moateff/2025_7_18_Eyeriss-v1-Data-Delivery-Pattarn-main/src
gcc run.c -o run.exe
./run.exe
# Produces: scheduler.txt, ifmap_index.txt, ifmap_address.txt, filter_index.txt, filter_address.txt, psum_index.txt, psum_address.txt
```

### Comparison to Final scheduler.sv (Project 4)

| Aspect | C Scheduler (P1) | RTL scheduler.sv (P4) |
|--------|------------------|----------------------|
| Language | C, file-based output | SystemVerilog, state machine |
| Loop depth | 3 levels (N, C, M) | 2 sets: outer (N, E, M) + inner (C, m) |
| Pass definition | M-range × C-range × N-range | Same concept but adds E (ofmap row) dimension |
| Output | Text file | Live bus signals (filter_ids, channel_ids, psum_ids) |
| E dimension | Not present | Added: `e` stride for psum/e partial sums |
| bias_sel | Not present | Added: selects bias vs psum for first channel |
| State control | Pure sequential C loops | 9-state FSM: IDLE→CHECK→OUTER_LOOP→INNER_LOOP→START_PASS→PROCESS→PASS_DONE→DUMPING→DONE |
| Processing control | Single pass expansion | Full loop: can iterate multiple passes, dump ofmaps |

**The core scheduling concept survived unchanged:** partition the convolution workload into passes defined by (filters_start, filters_end, channels_start, channels_end, ifmaps_start, ifmaps_end).

However, the final scheduler adds:
1. **E dimension** (ofmap row partial sums) as a separate loop
2. **m vs M distinction** (m = filters per outer loop, M = total filters)
3. **Dual-level control** (outer passes + inner passes = full pass count)
4. **Dump state** to write ofmaps back to GLB

---

## Project 2 (2025_7_23): Processing Element

### Files (25 source files + 32 test data files)

**RTL source (`src/`)**:
- `pe.v` (324 lines) -- Top-level PE with 3 SPADs, MAC, controller
- `pe_ctrl.sv` (188 lines) -- 6-state FSM controller
- `pe_wrapper.v` (204 lines) -- PE + 4 FIFOs + clock gating
- `ifmap_spad.v` (60 lines) -- Shift-register-based scratchpad (neg-latch write)
- `filter_spad.v` (52 lines) -- Simple BRAM-style filter memory
- `psum_spad.v` (32 lines) -- Dual-clock psum memory
- `zero_skipping.v` (49 lines) -- Parallel zero-detection buffer
- `signed_seq_multiplier.v` (90 lines) -- Signed sequential (Booth-style, 2-stage)
- `wallace_tree_multiplier.v` (49 lines) -- Wallace tree + CLA
- `carry_lookahead_adder.v` (33 lines) -- CLA with gen/propagate
- `truncator.v` (19 lines) -- Configurable truncator
- `mux2x1.v` (12 lines) -- 2:1 mux
- `dff.v` (17 lines) -- flopr (register with reset)
- `dff_en.v` (19 lines) -- flopenr (register with enable)
- `clk_gating.v` (20 lines) -- Latch-based clock gating
- `fifo_top.v` (103 lines) -- Width-flexible FIFO
- `fifo_wrapper.v` (70 lines) -- FIFO with width conversion
- `fifo_mem.v` (51 lines) -- FIFO memory with FWFT
- `fifo_rd_ctrl.v` (45 lines) -- FIFO read controller
- `fifo_wr_ctrl.v` (46 lines) -- FIFO write controller
- `fifo_flag_generator.v` (22 lines) -- Pulse-stretching enable
- `fifo_up_down_counter.v` (27 lines) -- Occupancy counter

**Testbench (`sim/`)**:
- `PE_tb.sv` (276 lines) -- Self-checking testbench for AlexNet Conv1

**Software (`sw/`)**:
- `run.c` (46 lines) -- Interactive C test program
- `1D_Convolution.c` (379 lines) -- Numpy-like 2D conv in C
- `Convert_to_binary.c` (100 lines) -- Integer→16-bit binary converter
- `Random_data.c` (33 lines) -- Random test data generator

**Test data (`.mem/`)**: 5 test cases:
- `conv1`: AlexNet Layer-1 (227x227, K=11x11, 64 filters, U=4 stride, n=1, p=16, q=1)
- `conv2`: Layer-2
- `conv3`: Layer-3
- `conv4,5`: Layers 4-5
- `example1`, `example2`, `example3`: Smaller test cases

### PE Architecture

The PE implements the Eyeriss V1 architecture at a single-PE level:

```
IFMAP_IN → [ifmap_spad (12 deep, shift-reg)] ┐
FILTER_IN → [filter_spad (224 deep, BRAM)]  ├→ [signed_seq_mul] → [truncator] → [adder/accum] → [psum_spad] → OPSUM_OUT
IPSUM_IN → [mux with truncator output]      ┘
Zero-skipping: parallel buffer tracks which ifmap entries are zero, gates read_enable
```

**SPADs**:
- **Ifmap SPAD** (12 entries): Shift register. On `shift`, data slides left by 1 position. On `write`, data writes at current pointer. This implements the "data re-use" Eyeriss feature -- previous ifmap entries slide down for the next row calculation. Uses `negedge clk`.
- **Filter SPAD** (224 entries): Standard BRAM. Linear write, random read. Depth = 224 to hold p*q*S = 16*1*11=176 (AlexNet), plus margin. Uses only 1 read port.
- **Psum SPAD** (24 entries): Dual clock (write @posedge, read @negedge). Two-cycle pipeline delay on control signals (`psum_addr_r`, `psum_addr_rr`, `wr_psum_rr`). Forwarding logic handles RAW hazard when same psum address is written and read in adjacent cycles.

**MAC Pipeline**:
1. **Signed sequential multiplier** (2-stage pipelined): Stage 1 splits `a` into low/high halves, computes two Wallace-tree products. Stage 2 adds them via CLA with shift, applies sign.
2. **Truncator**: Selectable truncation (sel=0 → LSBs kept, used for Q0.8→Q0.8)
3. **Accumulator**: CLA adder with mux path -- can add either truncated product or ipsum_pixel (for partial sum accumulation).

**PE Controller (6 states)**:
```
IDLE → PROCESS (MAC loop: i=0..S*q-1, j=0..p-1) → ACCUMULATE (add upstream psum) → STRIDE (shift ifmap by U*q) → PADDING (handle V=U*stride padding) → LOAD (reload ifmap for next n) → IDLE/PROCESS
```

- `PROCESS`: Performs `p * S * q` MAC operations (using data in SPADs)
- `ACCUMULATE`: For `p * F` cycles, adds upstream partial sums
- `STRIDE`: Shifts ifmap data by `U*q` positions (U = stride)
- `PADDING`: Handles the fact that E output rows use `E * U * U` input rows for 11x11 filters (V = p * F / 4 for 2x2 padding)
- `LOAD`: Resets ifmap SPAD for next ifmap, resets filter SPAD when all ifmaps done

### Testbench

The testbench (`PE_tb.sv`) tests a single PE with AlexNet Conv1 parameters:
- W=227, S=11, F=55, U=4 (stride), n=1, p=16, q=1
- Loads `.mem` files: `ifmap_data.mem` (n*W*q = 227 values), `filter_data.mem` (p*q*S = 176 values packed as 64-bit), `ipsum_data.mem` (p*n*F = 880 values packed as 64-bit), `expected_output.mem`
- Self-checking with pass/fail counters
- Does NOT check timing -- just final values

### Comparison to Final pe.v (Project 4)

| Aspect | P2 pe.v | P4 pe.v |
|--------|---------|---------|
| Module name | `pe` | `pe` (identical) |
| Config register | Yes (`flopenr cfg_inst` for W,S,F,U,n,p,q) | **Removed** -- configs wired directly |
| Parameter registers | `W_r`, `S_r`, etc. | **Removed** -- params used directly (e.g., `assign ifmap_spad_depth = q * S`) |
| Controller name | `pe_ctrl` | `pe_controller` (renamed) |
| Controller state names | identical (IDLE→PROCESS→ACCUMULATE→STRIDE→PADDING→LOAD) | identical |
| `start/await` signals | `start(~spads_empty)`, `await(spads_empty)` | `start(~spads_empty)`, `stall(spads_empty)` (renamed `await`→`stall`) |
| Multiplier name | `signed_seq_mul` | `multiplier` (simplified naming) |
| Adder name | `cla` | `adder` (simplified naming) |
| `V` calculation | `V_r = p_r[1:0] * F_r[1:0]` (registered) | `V = p[1:0] * F[1:0]` (combinational, recomputed each cycle) |
| Forwarding mux | `wr_psum_rr & (psum_addr_r == psum_addr_rr)` (inline) | `forward` wire (extracted for clarity) |
| Clock gating | Yes (`clk_gating` in pe_wrapper) | **Removed** |
| `busy` output | Yes (in `pe` top) | Yes |
| File type | Mixed .v / .sv | All .sv |

**The PE is essentially identical.** The main changes are:
1. Parameter registration removed (simpler, fewer flops)
2. Clock gating removed (simplifies timing)
3. Signal `await` renamed to `stall`
4. Module names simplified (`signed_seq_mul`→`multiplier`, `cla`→`adder`, `pe_ctrl`→`pe_controller`)

Notably, both versions use `negedge clk` for the PE controller state registers.

---

## Project 3 (2025_8_23): Network-on-Chip

### Files (12 files)

**NoC core**:
- `src/gin.sv` (76 lines) -- Global Input Network: 12 rows, 14 cols
- `src/gon.sv` (75 lines) -- Global Output Network: 12 rows, 14 cols
- `src/gin_mcc.sv` (33 lines) -- Multicast Controller (one per row or column)
- `src/gon_mcc.sv` (33 lines) -- Multicast Controller (output variant)
- `src/gin_xbus.sv` (38 lines) -- X-Bus: column fanout within a row
- `src/gon_xbus.sv` (38 lines) -- X-Bus (output variant)

**NoC wrappers with FIFOs**:
- `src/gin_fifo.sv` (90 lines) -- GIN + tag FIFO + data FIFO
- `src/gon_fifo.sv` (90 lines) -- GON + tag FIFO + data FIFO

**FIFO library** (subset of P2):
- `src/fifo_top.v` (79 lines) -- Stripped-down FIFO (no almost-full/empty)
- `src/fifo_mem.v` (51 lines) -- Identical to P2
- `src/fifo_rd_ctrl.v` (45 lines) -- Identical to P2
- `src/fifo_wr_ctrl.v` (46 lines) -- Identical to P2

**Build script**:
- `run.sh` (3 lines) -- iverilog compilation commands

### NoC Architecture

The NoC implements a **2-stage multicast routing tree**:

```
Stage 1 (GIN):                  Stage 2 (GON):
data_in → [MCC_row0] ┐          row_outputs ┌→ [XBus_col0] ┐
           [MCC_row1] ├→ XBus     →         └→ [XBus_col1] ├→ MCC_row → data_out
           [MCC_row2] │                        ...           │
           ...        ┘                        [XBus_col13] ┘
           [MCC_row11]
```

**GIN routing logic** (gin_mcc.sv):
- Each MCC has a hardcoded `id` (e.g., row 0 has id=0)
- Compares `q_id` (registered from `id`) against incoming `tag`
- If `equal_tag`: forwards data, asserts `enable_out`
- If not equal but upstream ready: passes `ready_out` through, blocks data
- **Tristate output**: GON MCC outputs `'bz` when not active (wired-OR bus)

**MCC ready chain**:
```
ready_out = ready_in | (!equal_tag)
```
An MCC reports "ready" if downstream is ready OR if it's not the target (passive pass-through). This allows the ready signal to propagate through non-target nodes.

**XBus**: A row of MCCs in parallel, each comparing against a column tag. All enabled simultaneously, all producing their own data_out/ready_out lines.

### GIN/GON with FIFOs

Both `gin_fifo` and `gon_fifo` add a **double-FIFO** pattern:
- **Data FIFO**: Holds the actual data payload (16-bit or 64-bit)
- **Tag FIFO**: Holds {col_tag, row_tag} in lockstep with data

Flow control:
```
enable_in = ready_out & (!data_empty) & (!tags_empty)
```
Both FIFOs read simultaneously when the GIN/GON is ready AND both have data. Both tags and data written with matching write-enables.

### Run Script

```bash
# FIFO testbench only
iverilog -o fifo -g2012 ./src/fifo_top.v ./src/fifo_mem.v ./src/fifo_rd_ctrl.v ./src/fifo_wr_ctrl.v
# GIN compilation (no testbench provided)
iverilog -o gin -g2012 ./src/gin_mcc.sv ./src/gin_xbus.sv ./src/gin.sv ./src/gin_fifo.sv ...
# GON compilation
iverilog -o gon -g2012 ./src/gon_mcc.sv ./src/gon_xbus.sv ./src/gon.sv ./src/gon_fifo.sv ...
```

**No standalone testbench exists.** The run.sh only compiles modules -- there is no simulation wrapper. The NoC cannot be tested standalone with this project; it is designed to be integrated with a PE array.

### Comparison to Final NoC (Project 4)

| Aspect | P3 NoC | P4 NoC |
|--------|--------|--------|
| GIN architecture | MCC(row) → XBus(col) | **Same** |
| GON architecture | XBus(col) → MCC(row) | **Same** (reverse) |
| gin_mcc.sv | ID loaded from wires, registered on negedge | **ID loaded via scan chain**, registered on posedge |
| gon_mcc.sv | Tristate `'bz` | **Same tristate pattern** |
| gin_fifo / gon_fifo | gin_fifo.sv, gon_fifo.sv | **Renamed** to gin_wrapper.sv / gon_wrapper.sv |
| FIFO type | `fifo_top` from P2 | `sync_fifo` (new, dedicated to NoC context) |
| Tag FIFO | Same pattern: {col_tag, row_tag} packed | **Same** |
| ID assignment | External wires | **Scan chain** serializes IDs |
| FIFO depth in wrapper | 16 (hardcoded) | 4096 (much deeper, for full layer) |
| `gin.sv` module interface | IDs as input ports | **IDs removed from ports** (internal to scan chain) |
| SystemVerilog features | Basic SV (no int params) | `parameter int`, `always_ff`, `always_comb` |
| Build target | iverilog (open-source) | Vivado (Xilinx) |

Key evolution:
1. **Scan chain** replaces hardwired IDs -- this is the biggest architectural change. Instead of routing 12+14*12 wires externally, IDs are loaded via a 1-bit serial chain.
2. **Deeper FIFOs** (16→4096) to handle full AlexNet layers
3. **Clock edge** changed from negedge to posedge for MCC ID register
4. **Wrapper renamed** (gin_fifo→gin_wrapper) but functionally identical
5. P4 **gin.sv** adds `enable_in` top-level port (in P3 it was implicit through the FIFO wrapper) and removes ID ports (now scan chain)

---

## Project 4 (2025_11_1): Final Full System

### Architecture Overview

```
EYERISS (eyeriss.sv)
├── SCAN_CHAIN (scan_chain.sv → scan_ff.sv)
├── SCHEDULER (scheduler.sv)  ← Evolved from P1 Scheduler.c
├── PROCESSING (processing_unit.sv)
│   ├── pe_array (pe_array.sv) ← 12×14 PE array
│   │   ├── 168× gin_wrapper (ifmap + filter + ipsum)
│   │   ├── 168× gon_wrapper (opsum)
│   │   └── 168× pe_wrapper → pe (pe.v) ← Evolved from P2
│   ├── noc_wrapper (noc_wrapper.sv)
│   │   ├── pass_controller (pass_controller.sv)
│   │   └── noc_controller (noc_controller.sv)
│   │       ├── ifmap_noc_controller (ifmap_noc_controller.sv)
│   │       │   ├── ifmap_index_generator (← P1 ifmap_index_generator.c)
│   │       │   ├── mapper (address computation)
│   │       │   ├── sync_fifo (collector)
│   │       │   └── ifmap_tag_generator
│   │       ├── filter_noc_controller (filter_noc_controller.sv)
│   │       │   ├── filter_index_generator (← P1 filter_index_generator.c)
│   │       │   ├── mapper
│   │       │   ├── sync_fifo
│   │       │   └── filter_tag_generator
│   │       ├── ipsum_noc_controller (ipsum_noc_controller.sv)
│   │       │   ├── psum_index_generator (← P1 psum_index_generator.c)
│   │       │   ├── mapper
│   │       │   ├── sync_fifo
│   │       │   └── psum_tag_generator
│   │       └── opsum_noc_controller (opsum_noc_controller.sv)
│   │           ├── psum_index_generator (reused)
│   │           ├── mapper
│   │           ├── sync_fifo (decollector)
│   │           └── psum_tag_generator
├── INTF (interface_unit.sv) ← New
│   ├── async_fifo.sv
│   ├── addr_generator.sv
│   ├── clk_mux.sv
│   ├── mux1.sv, mux2.sv, demux1.sv, demux2.sv
│   └── reset_sync.sv
├── GLB (glb_unit.sv) ← New
│   ├── ifmap_glb.sv (dual_bram)
│   ├── filter_glb.sv
│   ├── psum_glb.sv
│   └── bias_glb.sv
├── ReLU (relu_array.sv) ← New
└── config/ (per-layer config files) ← New
```

### What's Integrated from P1/P2/P3

**From Project 1 (C Data Delivery → RTL)**:

The C index generators are translated to SystemVerilog virtually 1:1:

| C Function (P1) | RTL Module (P4) | Key Changes |
|-----------------|-----------------|-------------|
| `ifmapAddressGenerator()` | `ifmap_index_generator.sv` | Loop order preserved: n→W→q→D→r (H renamed to D). FSM replaces C while-loop with `await` handshake. |
| `filterAddressGenerator()` | `filter_index_generator.sv` | Lock/register pattern preserved. Inner 4-element loop preserved (i=0..3). p→q→S cascade identical. OUTER_LOOP handles R→r→t transitions. |
| `psumAddressGenerator()` | `psum_index_generator.sv` | Lock/register pattern preserved. Same p→F→n cascade. At DONE, updates `m += p*t` same as C. |
| `scheduler()` | `scheduler.sv` | 3-level → 5-level state machine. psum_index_generator `channel_index` uses `m_crnt + p_crnt + t_crnt*p` matching C's `m + p_ind + t_ind*p`. |
| `calculateAddress()` | `mapper.sv` | 4D→1D address: `idx4*dim3*dim2*dim1 + idx3*dim2*dim1 + idx2*dim1 + idx1`. C version computed pointer offset; RTL computes GLB address. |

The **filter/psum index generator algorithm** is the most faithfully preserved. The "register" pattern (save indices, process 4 inner elements, restore) maps directly to the OUTER_LOOP state that saves `S_reg`, `p_reg`, `q_reg` and restores them in the next iteration.

**From Project 2 (PE → PE Array)**:

The PE is reused with only cosmetic changes (see detailed comparison above). The pe_wrapper is also preserved nearly identically:
- P2 pe_wrapper: PE + 4 FIFOs + clock gating
- P4 pe_wrapper: PE + 4 sync_fifos (no clock gating)

The SPAD designs (`ifmap_spad.v`, `filter_spad.v`, `psum_spad.v`) are reused verbatim (or with trivial naming changes).

**From Project 3 (NoC → Full NoC Controller)**:

The GIN/GON routing fabric (`gin.sv`, `gon.sv`, `gin_mcc.sv`, `gon_mcc.sv`, `gin_xbus.sv`, `gon_xbus.sv`) is reused with these changes:
1. IDs loaded via scan chain instead of external wires
2. `gin_mcc` register moves from negedge to posedge clock
3. Ready chain logic identical (`ready_out = ready_in | !equal_tag`)
4. Tristate GON output identical (`'bz` when inactive)

The gin_fifo and gon_fifo wrappers evolve to gin_wrapper and gon_wrapper with deeper FIFOs (16→4096).

### What's New in Project 4

1. **Full scheduler state machine** (`scheduler.sv`): 9-state FSM with separate outer (N/E/M) and inner (m/C) loop control. Adds `ofmap_dump`/`dump_done` handshake, `bias_sel` for first-channel accumulation.

2. **Four complete NoC controller pipelines** (ifmap, filter, ipsum, opsum):
   - Each combines: index generator + mapper (address) + collector FIFO + tag generator
   - Flow control: `await(collector_full)` pauses index generation when downstream is full
   - Opsum uses "decollector" pattern (FIFO before writeback to GLB)

3. **GLB Unit** (`glb_unit.sv`): 4 independent buffers
   - Ifmap GLB (7945 entries): Dual-port, A=64bit write, B=16bit read
   - Filter GLB (3872 entries): Dual-port, A=64bit write, B=16bit read
   - Psum GLB (46656 entries): Dual-port, A=read(64b)/write(16b), B=16bit read
   - Bias GLB (64 entries): Simple read port

4. **Interface Unit** (`interface_unit.sv`): Async FIFO bridge between `core_clk` and `link_clk` domains. Handles DRAM→GLB (forward) and GLB→DRAM (backward) data transfers. Uses `reset_sync` for CDC safety.

5. **Scan Chain** (`scan_chain.sv`): Serial configuration. Loads all 16 mapping parameters (H, W, R, S, E, F, C, M, N, U, m, n, e, p, q, r, t) and PE IDs via 1-bit serial input.

6. **ReLU** (`relu_array.sv`): Applies ReLU to ofmap data during GLB→DRAM readout.

7. **Tag Generators**: New modules for each data type:
   - `ifmap_tag_generator`: Computes row_tag = row_index/U, col_tag = col_index + r_index * F
   - `filter_tag_generator`: Maps filter location to target PE grid coordinate
   - `psum_tag_generator`: Maps psum location to source PE grid coordinate

8. **Pass Controller** (`pass_controller.sv`): Simple 4-state FSM that gates `start` → `start_nocs` and waits for `nocs_done`.

9. **Configuration system** (`config/`): Per-layer parameter files (conv1 through conv5), plus per-layer ID assignments (ifmap_ids, filter_ids, psum_ids), local network selectors, scan chain initialization data, and enables.

### What Changed vs. Earlier Projects

| Component | P1/P2/P3 | P4 | Reason |
|-----------|----------|----|----|
| Scheduler | "one pass and break" | Full multi-pass iteration | Correctness: P1 had a bug |
| E dimension | Absent | Present (psums indexed by ofmap row) | Needed for real convolutions (U>1 stride) |
| Config method | C: compiler constants, P2: static port wires | Bit-serial scan chain | Necessary for configurable accelerators |
| Clock edge (MCC) | negedge | posedge | Standardization with rest of design |
| FIFO depth | 16 entries | 4096 entries | Real layer sizes (227×227×3 ifmap) |
| `Q_r` (ifmap channels per PE) | Registered each cycle | Combinational | Simplification (speed vs. timing) |
| Lock mechanism C→RTL | C static vars in while-loop | FSM state register | Hardware-appropriate translation |
| Processing pass count | 1 (bug: break) | All passes iterated | Necessary for full convolution |
| Data type width m | 6 bits | 8 bits | Accommodates larger M values (64 filters) |
| Tag generators | Separate C functions | RTL modules | Different decomposition in hardware |
| Pass controller | Not present | Added | Separates timing concern from noc_controller |

### Bugs Fixed

1. **P1: Only one pass processed.** The `break;` on line 141 of `run.c` causes early termination. Fixed in P4 by the scheduler's FSM implementing full loop iteration.

2. **P2: Clock gating removed.** The latch-based clock gating (`clk_gating.v`) can cause glitches and is generally discouraged in modern FPGA design. P4 removes it entirely.

3. **P2: Mixed clock edges.** The PE uses `negedge` for most registers but `posedge` for psum_spad write. This creates potential for hold-time violations. P4 standardizes more registers to `posedge` (e.g., scheduler, gin_mcc).

4. **P2: File reading uses `readmemb` (binary).** But the .mem test files contain ASCII binary strings. This works in Verilog simulation but is fragile.

5. **P3: No testbench.** The NoC project cannot be tested standalone -- modules compile but there's no stimulus. P4 provides a full system testbench.

6. **P4 scheduler.sv: `always_ff @(posedge clk)` used.**
But the `modport` and other sub-modules (pe_controller) use `negedge` -- mixed clock edges cause timing complications.

### Reusability Assessment

**Directly reusable:**
- `ifmap_spad.v`, `filter_spad.v`, `psum_spad.v` (from P2, unchanged in P4)
- `mux2x1.v`, `dff.v`, `dff_en.v` (basic primitives)
- `gin.sv`, `gon.sv` core routing logic (architecture identical, minor port changes)
- `gin_mcc.sv`, `gon_mcc.sv` (same logic, clock edge changed)
- `truncator.v`, `wallace_tree_multiplier.v` (combinational, no changes needed)
- `fifo_top.v` / `sync_fifo` FIFO control logic (same concept)

**Partially reusable (needs adaptation):**
- `pe.v` (P2): Remove config register, rename controller
- `pe_ctrl.sv` (P2): Rename `await` to `stall`, simplifies `V` calculation
- `signed_seq_multiplier.v` (P2): Rename to `multiplier`, same core
- `gin_fifo.sv` / `gon_fifo.sv` (P3): Deepen FIFOs, add scan chain, rename to `_wrapper`
- `index_generator.c` (P1): Algorithm is correct, translate to RTL FSM

**Not reusable (major redesign):**
- P1 scheduler (C): Only processes one pass, lacks E dimension -- algorithm needs redesign
- P2 `clk_gating.v`: Removed entirely in P4
- P2 `pe_wrapper.v`: Clock gating removed, FIFOs changed to sync_fifo
- P3 wiring of PE IDs: Replaced by scan chain

### Using the C Model to Validate Final RTL

The C index generators (P1) could be used as a golden reference for the RTL index generators (P4):

1. **Compile P1** to produce `ifmap_index.txt`, `filter_index.txt`, `psum_index.txt`
2. **Modify P1** to remove the `break;` bug and add the E (ofmap row) dimension
3. **Simulate P4** in Verilator/Vivado with the same parameters, dump index values
4. **Compare** cycle-by-cycle: C output vs. RTL output should match

The C address values (pointer offsets) would need to be remapped to GLB addresses (byte addresses), but the index sequence should be identical.

However, there are differences:
- P1's `ifmapAddressGenerator` uses `H` (ifmap height), while P4's uses `D = (e << (U >> 1)) + R - U` (the "data delivery height" -- a different dimension accounting for stride)
- P1's filter generator computes `filter_index = filter_start + p_ind + t_ind*p`, while P4 computes `filter_index = p_crnt + t_crnt * p`. These are equivalent if the start offset is managed externally.

**In practice**, the best validation approach would be:
1. Fix P1's break bug
2. Run it for small parameters
3. Export the index sequences
4. Use those as expected values in a Verilator testbench for the P4 index generators

---

## Summary Evolution Timeline

```
2025_7_18: C Data Delivery
├── Scheduler: 3-level loop partitioning (M/C/N)
├── Index generators: ifmap (5-nested), filter (lock pattern), psum (lock pattern)
├── Address calculator: 4D→1D pointer offset
└── Output: text files per component per cycle

         ↓ (5 days later)

2025_7_23: Processing Element
├── PE: 3 SPADs + MAC pipeline + 6-state FSM controller
├── Digital building blocks: Wallace multiplier, CLA adder, shift-reg SPADs
├── FIFO library: width-flexible, FWFT, dual-clock
├── Testbench: AlexNet Conv1, self-checking
└── Software: C reference conv + binary file generator

         ↓ (1 month later)

2025_8_23: Network-on-Chip
├── GIN: MCC(row) → XBus(col) multicast routing
├── GON: XBus(col) → MCC(row) gather routing (tristate bus)
├── FIFO wrappers: tag+data double-FIFO pattern
├── 12×14 grid routing (AlexNet PE array dimensions)
└── No testbench -- building block only

         ↓ (2.5 months later)

2025_11_1: Final Full System
├── Integration of P1+P2+P3 components
├── NEW: scheduler.sv (5-level FSM)
├── NEW: GLB subsystem (4-port memory hierarchy)
├── NEW: Interface unit (async FIFO bridge)
├── NEW: Scan chain (config serialization)
├── NEW: ReLU array
├── NEW: Tag generators (3 types)
├── NEW: Full system testbench with config packages
├── REUSED P2: PE + SPADs (minor renames)
├── REUSED P3: GIN/GON routing (scan chain ID loading)
└── TRANSLATED P1: Index generators (C→RTL, bug fixed)
```

**Total source files**: P1=7, P2=25+32data, P3=12, P4=~60 (src only) + ~40 configs + ~10 sim + ~15 model

**Key design decisions that persisted**:
1. Row-stationary dataflow (data stays in PE SPADs)
2. p*q*r*t processing pass partitioning
3. Double-FIFO pattern for NoC tags+data
4. 4-element inner loop (packing 4 16-bit values into 64-bit words)
5. Lock/register pattern in filter/psum index traversal
6. Tristate output for GON collection bus
