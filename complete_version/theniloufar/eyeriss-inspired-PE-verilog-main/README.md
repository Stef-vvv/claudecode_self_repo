
# Eyeriss-Based Accelerator Project – Complete Documentation

This repository presents a structured, three-phase hardware design project inspired by the **Eyeriss architecture**, implemented in Verilog. At the heart of all phases is a robust, parameterized **Circular FIFO Buffer** system, enabling high-performance and synchronized data communication across all architectural layers.

---

## Core Foundation: Circular FIFO Buffer

### Purpose

The **Circular FIFO Buffer** is the central component used across all three phases. It provides:
- Parameterized buffer depth and parallelism
- Overflow/underflow protection
- Handshake-based communication (`valid`, `ready`, `en_read`, `en_write`)
- Support for simultaneous parallel reads and writes

### Components

- `buffer.v`, `circular_buffer.v`: Base buffer logic
- `components.v`: Shared building blocks (memory arrays, muxes)
- `controller.v`: Control flow for enabling reads/writes and detecting full/empty states
- `datapath.v`: Implements address calculation and pointer logic
- `toplevel.v`: Integrates datapath and controller
- `testbench.sv`: Verifies correctness under various access patterns

This buffer architecture supports **parallel data access**, and its design is reused and expanded in all three phases of the Eyeriss accelerator.

---

## Phase 1: Buffer Design and Control

### Objective

Establish foundational infrastructure for memory-aware processing. Implements:
- FIFO and circular buffer systems
- Simple datapath and controllers
- Scratchpad memory for intermediate data
- Testbenches for simulation and validation

### Key Files

- `buffer.v`, `circular_buffer.v`: FIFO modules
- `datapath.v`: Basic arithmetic/logic structure
- `main_controller.v`, `buffer_controller.v`: FSM-based control
- `testbench.v`, `testbench_second.v`, `testbench_third.v`: Simulation

### Highlights

- Focus on modularity and reusability
- Wrap-around logic with modular addressing
- Configurable parallel read/write widths

---

## Phase 2: Processing Element and Buffer Architecture

### Objective

Extend Phase 1 into a **Processing Element (PE)** with a functioning control pipeline and refined dataflow coordination.

### Key Files

- `datapath.v`: Upgraded ALU datapath
- `buffer_controller.v`: Advanced read/write coordination
- `data_read_controller.v`, `filter_read_controller.v`: Memory interface modules
- `firstmodetb.v`: Verilog testbench

### Simulation Example

```bash
iverilog -o testbench.vvp firstmodetb.v *.v
vvp testbench.vvp
gtkwave dump.vcd
```

### Notes

- Circular buffer is reused with updated control integration
- Enables more complex memory-fetch and filter load operations

---

## Phase 3: Integrated Processing Element

### Objective

Combine datapath, buffer system, and control logic into a **fully functional PE**, capable of top-level simulation and synthesis.

### Key Files

- `PE.v`: Complete PE module integrating all components
- `controller_global.v`: Oversees full system control
- `toplevel.v`: Wraps and connects all submodules
- `testbench.v`: End-to-end simulation driver

### Simulation

```bash
iverilog -o sim testbench.v *.v
vvp sim
gtkwave dump.vcd
```

### Design Features

- Full integration with circular buffer as data movement backbone
- Global and local FSM control layers
- Configurable and testable PE unit

---

## Summary of Design Evolution

| Phase      | Key Focus                                   | Role of Circular Buffer                     |
|------------|---------------------------------------------|---------------------------------------------|
| Phase 1    | Buffer + Datapath + Scratchpads             | Foundation: parallelism and memory handling |
| Phase 2    | PE Core: Coordination of data and control   | Extended reuse with controller interface    |
| Phase 3    | Final PE Integration and Top-Level Testing  | Backbone of full PE memory interaction      |

---

## Reference

> Chen et al., “Eyeriss: An Energy-Efficient Reconfigurable Accelerator for Deep Convolutional Neural Networks,” IEEE Journal of Solid-State Circuits, 2016.
