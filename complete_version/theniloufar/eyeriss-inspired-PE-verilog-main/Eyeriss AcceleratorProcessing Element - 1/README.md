# Eyeriss Accelerator – Phase 1: Buffer Design and Control

## Overview

This phase focuses on laying the foundation of the Eyeriss-inspired accelerator by implementing **buffer systems**, **basic datapath modules**, and **simple control logic**. It sets up the infrastructure for memory-aware processing, necessary for data reuse and energy efficiency in spatial accelerators.

---

## Project Structure

```
Eyeriss AcceleratorProcessing Element - 1/
├── buffer.v                   # FIFO buffer implementation
├── circular_buffer.v         # Circular buffer with wrap-around logic
├── buffer_controller.v       # Manages buffer access and flow control
├── datapath.v                # Simple processing datapath
├── data_read_controller.v    # Controls data input
├── filter_read_controller.v  # Controls weight input
├── main_controller.v         # Main control FSM for top-level coordination
├── scratchpads.v             # Temporary data holding units (register arrays)
├── counters.v                # Modular counters for synchronization
├── components.v              # Logic components (adder, mux, etc.)
├── testbench.v               # First testbench
├── testbench_second.v        # Extended/alternate test scenario
├── testbench_third.v         # More complex simulation testbench
├── toplevel.v                # Integrates all modules for simulation
├── Instruction.pdf           # Phase 1 design brief
```

---

## Key Modules

### Buffers

- **`buffer.v`** and **`circular_buffer.v`** implement FIFO-style storage units
- Fully synchronized with valid-ready protocol
- Empty/full status flags and flow control logic

### Controllers

- **`buffer_controller.v`**: Interface between computation and buffer
- **`data_read_controller.v`** & **`filter_read_controller.v`**: Control memory reads

### Datapath

- **`datapath.v`**: A primitive datapath linking ALUs and memory ports

### Scratchpads

- Implements fast-access memory for filter and input storage

### `main_controller.v`

- Finite State Machine (FSM) managing module coordination

---

## Testbenches

- `testbench.v`: Basic buffer and datapath check
- `testbench_second.v`: Tests sequencing with multiple data inputs
- `testbench_third.v`: Stress test with full datapath and memory ops

Use these to validate each part of the architecture in isolation or in composition.

---

## How to Simulate

1. Install a simulator like Icarus Verilog or ModelSim
2. Run simulation with:

```bash
iverilog -o sim_output testbench.v *.v
vvp sim_output
```

3. Optionally visualize signals with GTKWave:

```bash
gtkwave dump.vcd
```

---

## Notes

- This phase lays the **hardware micro-architecture** foundation with reusable primitives.
- Emphasizes modular buffer design, reusability, and separation of concerns.
- Includes **instruction document** guiding this phase's implementation logic and block diagram assumptions.

---

## Transition to Phase 2

Phase 2 integrates these modules into a more cohesive **Processing Element** with enhanced control, filtering logic, and dataflow orchestration.

---

## Reference

Based on the Eyeriss architecture by:

> *Chen et al., “Eyeriss: An Energy-Efficient Reconfigurable Accelerator for Deep Convolutional Neural Networks,” IEEE JSSC, 2016.*
