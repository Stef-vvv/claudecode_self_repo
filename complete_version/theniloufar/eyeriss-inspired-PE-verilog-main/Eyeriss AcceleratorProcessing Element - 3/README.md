# Eyeriss Accelerator – Phase 3: Integrated Processing Element (PE)

## Overview

This phase delivers a fully integrated **Processing Element (PE)** architecture based on the Eyeriss accelerator. Building on the buffer and control modules from Phases 1 and 2, Phase 3 introduces **global control**, **handshaking**, and **top-level integration** with testbenches simulating end-to-end functionality.

---

## Project Structure

```
Eyeriss AcceleratorProcessing Element - 3/
├── buffer.v                    # FIFO buffer logic
├── circular_buffer.v          # Circular buffer for wrap-around access
├── buffer_controller.v        # Manages buffer read/write interface
├── controller_global.v        # Orchestrates global timing and PE control
├── datapath.v                 # Arithmetic and register datapath
├── PE.v                       # Complete PE instantiation (core module)
├── main_controller.v          # Local FSM for computation sequence
├── data_read_controller.v     # Manages input data loading
├── filter_read_controller.v   # Manages filter loading
├── scratchpads.v              # Local memory units (SRAM-like)
├── components.v               # Combinational logic modules
├── counters.v                 # Modular counters for FSM timing
├── mux2.v                     # 2-input multiplexer module
├── toplevel.v                 # System wrapper with full integration
├── testbench.v                # PE simulation with functional stimuli
├── Instruction.pdf            # Final design specification for Phase 3
```

---

## 🔧 Key Modules

### `PE.v`

- Encapsulates the entire **Processing Element logic**
- Interfaces with external buffers, scratchpads, and controllers

### `controller_global.v`

- Coordinates top-level operation and handshaking

### `toplevel.v`

- Instantiates and connects all modules for simulation

---

## How to Run the Simulation

```bash
iverilog -o sim testbench.v *.v
vvp sim
gtkwave dump.vcd  # optional
```

---

## Design Highlights

- Handshake protocols between memory and compute units
- Layered buffer hierarchy
- Configurable and modular PE design

---

## Summary of All Phases

- **Phase 1**: Buffer and primitive datapath infrastructure
- **Phase 2**: Buffer + controller + datapath integration
- **Phase 3**: Full PE with top-level control and simulation

---

## Reference

> *Chen et al., “Eyeriss: An Energy-Efficient Reconfigurable Accelerator for Deep Convolutional Neural Networks,” IEEE Journal of Solid-State Circuits, 2016.*
