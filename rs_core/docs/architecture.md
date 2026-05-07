# RS Dataflow Accelerator — Architecture Document

## 1. Overview

This project implements a simplified **Row Stationary (RS) dataflow** convolution accelerator inspired by the Eyeriss architecture. The design processes 3×3 convolution layers with configurable bit widths.

**Key specifications:**
- Input feature map: 5-bit quantization (Q_IN=5)
- Filter weights: 8-bit quantization (Q_W=8)
- Accumulated results: 16-bit (ACC_WIDTH)
- PE Array: 3×3 systolic array
- One PE array processes a 5×3 input tile to produce a 3×3 output tile

## 2. Module Hierarchy

```
rs_top.v
├── Scheduler_RS (scheduler_rs.v)
│   └── FSM control: IDLE → FEED0 → FEED1 → FEED2 → DRAIN → DONE
├── PE_Array (pe_array.v)
│   └── 9 × PE (pe.v) — 3×3 systolic grid
└── Aggregator (aggregator.v)
    └── Partial sum accumulation
```

## 3. PE (Processing Element)

### 3.1 Architecture

Each PE computes a 3-element sliding-window dot product over 5 input data values:

```
data[0:4] × filter[0:2]:
  dot(0) = data[0]*filt[0] + data[1]*filt[1] + data[2]*filt[2]
  dot(1) = data[1]*filt[0] + data[2]*filt[1] + data[3]*filt[2]
  dot(2) = data[2]*filt[0] + data[3]*filt[1] + data[4]*filt[2]
```

### 3.2 State Machine (5 cycles per computation)

| State | Cycle | Operation |
|-------|-------|-----------|
| IDLE  | —     | Wait for start signal |
| IDLE+start | 0 | Latch data/filter (if new_in_data=1), compute dot(0), out_start=1 |
| MAC   | 1 | Compute dot(1), clear out_start |
| MAC   | 2 | Compute dot(2), transition to ACC |
| ACC   | 3 | Accumulate in_result from above PE, finished=1 |
| DONE  | 4 | Clear finished, return to IDLE |

### 3.3 Interface

```
Inputs:  start, new_in_data, in_data[4:0], in_filter[2:0], in_result[2:0]
Outputs: out_result[2:0], out_filter[2:0], out_start, finished
```

## 4. PE Array (3×3 Systolic Array)

### 4.1 Dataflow

```
Data:     BROADCAST to all 9 PEs (same bus)
Filter:   RIGHT propagation from column 0
Psum:     DOWN propagation from row 0
Start:    DIAGONAL propagation: start[r][c] = out_start[r][c-1] | out_start[r-1][c]
```

### 4.2 RS Simplification

In true Eyeriss Row Stationary, data is shared **diagonally** between PEs. In this implementation, data is **broadcast** to all PEs. The scheduler controls *which* data is on the bus at *which* cycle, and the start propagation determines *which* PEs latch the data.

This means:
- Only the **first column** of PEs produces meaningful results
- The other 6 PEs (columns 1,2) perform motion-simulating computation but their outputs are not used
- The array outputs one row of the output feature map per tile
- This is a **valid simplification** that preserves the RS timing and control structure while reducing wiring complexity

### 4.3 Timing (one 3×3 tile)

| Cycle | Data Bus | Filter Bus | PEs receiving start | PEs latching |
|-------|----------|------------|---------------------|--------------|
| 0 | ifmap row 0 | filter row 0 | PE(0,0) | PE(0,0) |
| 1 | ifmap row 1 | filter row 1 | PE(0,1), PE(1,0) | PE(0,1), PE(1,0) |
| 2 | ifmap row 2 | filter row 2 | PE(0,2), PE(1,1), PE(2,0) | PE(0,2), PE(1,1), PE(2,0) |
| 3 | — | — | PE(1,2), PE(2,1) | none (new_in_data=0) |
| 4 | — | — | PE(2,2) | none |
| 5 | — | — | — | PE(0,0) finishes |
| 6 | — | — | — | PE(1,0) finishes |
| 7 | — | — | — | PE(2,0) finishes → output ready |

## 5. Scheduler

The scheduler is a finite state machine that feeds data to the PE array:

```
IDLE: wait for start_cmd
FEED0: present row0 data + row0 filter, assert start_global + new_in_data
FEED1: present row1 data + row1 filter
FEED2: present row2 data + row2 filter, deassert new_in_data
DRAIN: wait for array_finished
DONE: capture result, return to IDLE
```

For a full convolution layer, the scheduler iterates over:
- Input channels (C=32)
- Spatial tiles (rows and columns)
- Output channels (F=64)

## 6. File Structure

```
rs_core/
├── py/
│   ├── pe.py           — PE behavioral model
│   ├── pe_array.py     — 3×3 PE array model
│   ├── scheduler.py    — Data flow control
│   ├── bram.py         — Block RAM model
│   ├── aggregator.py   — Output accumulation
│   ├── write_to_ram.py — Write-back to BRAM
│   └── top.py          — Top-level integration
├── py_tests/
│   ├── pe_test.py      — PE unit tests (6 tests)
│   ├── pe_array_test.py — PE array tests (4 tests)
│   ├── scheduler_test.py — Scheduler integration tests
│   └── top_test.py     — Full pipeline test
├── rtl/
│   ├── pe.v            — PE synthesizable Verilog
│   ├── pe_array.v      — PE Array synthesizable Verilog
│   ├── scheduler_rs.v  — Scheduler FSM
│   ├── aggregator.v    — Output aggregator
│   └── rs_top.v        — Top-level integration
├── tb/
│   ├── pe_tb.v         — PE testbench
│   ├── pe_array_tb.v   — PE Array testbench
│   └── rs_top_tb.v     — System testbench
├── wavedrom/
│   ├── pe_wavedrom.json        — PE timing diagram
│   └── pe_array_wavedrom.json  — Array timing diagram
└── docs/
    └── architecture.md  — This document
```

## 7. Test Results Summary

### Python Tests (all passing)

| Test | Result |
|------|--------|
| PE: Basic MAC | [14, 20, 26] ✓ |
| PE: MAC+ACC | [17, 36, 55] ✓ |
| PE: Timing/FSM | 5-cycle sequence ✓ |
| PE: Data Latching | new_in_data gating ✓ |
| PE: Back-to-Back | Multiple ops ✓ |
| PE: Column Accumulation | [411, 456, 501] ✓ |
| PE Array: Same Data | [42, 60, 78] ✓ |
| PE Array: RS Emulation | [411, 456, 501] ✓ |
| PE Array: Selective new_in_data | [411, 456, 501] ✓ |
| PE Array: Output Timing | Correct cycle ✓ |
| Scheduler: Single Tile | [411, 456, 501] ✓ |
| Scheduler: Simple Tile | [18, 27, 36] ✓ |
| Scheduler: Back-to-Back | Correct ✓ |
| Top: Full Pipeline | 3×3 OFM correct ✓ |

## 8. Synthesis Notes

- All Verilog uses synthesizable constructs: `always_ff`, `always_comb`, `generate`, `case`
- No `for` loops in procedural code (only `generate` for blocks)
- State machines use `localparam` encoding
- Multipliers inferred as combinational logic (synthesis tool will map to DSP blocks)
- Reset is active-low asynchronous (`negedge rst_n`)
- All registers initialized on reset
