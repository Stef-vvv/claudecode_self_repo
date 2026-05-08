# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Row-Stationary (RS) dataflow convolution accelerator based on Eyeriss V1.
Graduation project: simplified 6-array RS accelerator for 2D conv (Layer-3: 16×16×32→16×16×64, K=3×3).

Two-layer verification: Python behavioral model + synthesizable Verilog RTL.

## Active Directories

- `rs_project/` — Final consolidated project (Python + RTL + tests + docs)
- `rs_ed1/` — Latest RTL redesign per MD spec (cleaner scheduler/aggregator)
- `rs_core/`, `py_project/` — Earlier iterations (reference only, do not modify)
- `H:/project/Python_RS/` — Original reference Python project (read-only, has known bugs)
- `H:/project/RS-verilog_files/` — Original reference RTL (incomplete, different architecture)

## Key Architecture (Simplified RS)

**Data broadcast** to all 9 PEs in 3×3 array. Scheduler time-multiplexes 3 ifmap rows + 3 filter rows across 3 cycles. Start signal propagates diagonally (out_start from left OR above). Only column 0 produces valid results; columns 1-2 are redundant (design intent — trades 2/3 PE utilization for simpler wiring).

**6-array extension**: Each array gets a different 5-element slice of 18-element padded ifmap row (stride 3). Aggregator concatenates 6×3=18 pixels → 16-pixel output row (last array only contributes pixel 15).

## Running Tests

### Python (rs_project/)

```bash
cd H:\cc_project\rs_project
python py_tests/pe_test.py          # PE: 4/4 expected
python py_tests/pe_array_test.py    # PE Array: 3/3 expected
python py_tests/top_test.py         # Top: 3/3 expected
```

### RTL Simulation (Vivado 2020.2)

Vivado path: `E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin`

```bash
# PE only
cd H:\cc_project\rs_ed1\tb
E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin/xvlog ../rtl/pe.v ../rtl/pe_array.v ../rtl/scheduler_6array.v ../rtl/aggregator_6array.v ../rtl/rs_top_6array.v tb_rs_top.v
E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin/xelab -L xil_defaultlib -s ed1_sim tb_rs_top
E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin/xsim ed1_sim -R
```

## RTL Design Rules

1. **No `for` or `generate`** — all loops expanded manually
2. **No SystemVerilog** — pure Verilog-2001 (no `always_ff`, no `.name` implicit ports)
3. **All posedge clk** — no negedge registers; outputs driven by `case(nxt_state)` combinational logic, registered at posedge
4. **`nxt_state`-driven outputs**: Scheduler outputs use `case(nxt_state)`, not `case(state)`. This ensures data is stable one cycle before PE samples it
5. **`any_finished` must be combinational wire** (`assign any_finished = f0|f1|...`), NOT a registered output — otherwise aggregator misses the capture window
6. **PRELOAD state before FEED0**: One cycle to pre-load data bus before asserting start_global

## Data Format

All data files use Q0.8 fixed-point (step = 1/256, range [-0.5, 0.496]). Golden reference verified 16384/16384 against numpy integer computation (Q8 MAC → shift-right-8 → symmetric saturate [-127,127], NO ReLU).

| File | Values | Layout |
|------|--------|--------|
| conv2.input.real.dat | 8,192 | 32ch × 16×16 (ch-major) |
| conv2.real.dat | 18,432 | 64oc × 32ic × 3×3 (oc-major) |
| conv2.output.real.dat | 16,384 | 64oc × 16×16 (oc-major) |

## Known Issues (do not hide)

- Full conv2 Python output has ~2% 1-LSB deviation from golden (float vs Q8 integer precision)
- 6-array RTL only verified for single tile; full conv2 loop (ic/tile/oc FSM) not yet designed
- BRAM interface not integrated; testbenches feed data directly
- `IN_WIDTH=5` parameter name is misleading (actual data is Q0.8 = 8-bit)
- PE Array columns 1-2 produce redundant computation (simplified RS design, not a bug)
- pe_array_tb had deceptive mid-test reset — fixed by using natural pipeline drain instead
