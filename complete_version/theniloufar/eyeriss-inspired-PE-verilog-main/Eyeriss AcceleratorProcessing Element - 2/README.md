# Eyeriss Accelerator – Phase 2: Processing Element and Buffer Architecture

## Overview

This phase focuses on implementing the **Processing Element (PE)** architecture inspired by the Eyeriss accelerator, with a particular emphasis on **buffer designs**. The goal is to support efficient dataflow and parallel processing through modular and reusable Verilog components.

This stage builds upon Phase 1 and introduces control and datapath logic with buffer coordination, aligned with Eyeriss’s spatial architecture for energy-efficient deep learning.

---

## Project Structure

```
Eyeriss AcceleratorProcessing Element - 2/
├── buffer.v                    # Simple FIFO buffer
├── circular_buffer.v          # Circular FIFO buffer
├── buffer_controller.v        # Controls reading/writing to buffers
├── data_read_controller.v     # Manages data loading from SRAM
├── filter_read_controller.v   # Controls filter weight loading
├── datapath.v                 # Main processing datapath of the PE
├── counters.v                 # Various counter modules
├── components.v               # Reusable combinational modules
├── firstmodetb.v              # Verilog testbench for simulation
├── Instruction.pdf            # Design specification for Phase 2
```

---

## Key Components

### `buffer.v`

Implements a basic FIFO buffer for storing intermediate data.

### `circular_buffer.v`

Implements a circular version of the FIFO buffer with efficient pointer management.

### `buffer_controller.v`

Coordinates buffer read/write actions and synchronizes multiple buffers.

### `datapath.v`

Connects processing components such as multipliers, adders, registers.

### `data_read_controller.v` & `filter_read_controller.v`

Control modules to fetch input data and filter weights with proper sequencing.

---

## Testbench

- `firstmodetb.v`: Validates buffer functionality and module interaction

---

## Running the Simulation

```bash
iverilog -o testbench.vvp firstmodetb.v *.v
vvp testbench.vvp
gtkwave dump.vcd  # Optional waveform
```

---

## Notes

- Buffers support both linear and circular modes
- Design aligns with modular reuse and control-driven dataflow
- Forms the backbone of the PE's spatial processing core

---

## Reference

> *Chen et al., “Eyeriss: An Energy-Efficient Reconfigurable Accelerator for Deep Convolutional Neural Networks,” IEEE Journal of Solid-State Circuits, 2016.*
