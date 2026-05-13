#!/bin/bash
#
# run_pe.sh — Compile, elaborate, and run the PE standalone test.
#
# Prerequisites:
#   - Vivado 2020.2 installed at E:/VIVADO_Download/VIVADO/Vivado/2020.2
#   - Python available as 'python'
#
# Usage:
#   cd H:/moateff_test/pe_standalone
#   bash run_pe.sh
#

set -e

# ------------------------------------------------------------------
# Paths
# ------------------------------------------------------------------
VIVADO_BIN="E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin"
PROJECT_DIR="H:/moateff_test/pe_standalone"
SRC_DIR="$PROJECT_DIR/src"
SIM_DIR="$PROJECT_DIR/sim"
PY_DIR="H:/moateff_test/py"

# ------------------------------------------------------------------
# Step 0: Generate .mem test vectors
# ------------------------------------------------------------------
echo "========================================"
echo " Step 0: Generate .mem test vectors"
echo "========================================"
cd "$SIM_DIR"
python "$PY_DIR/gen_pe_mem.py"
echo ""

# Clean up any previous build artifacts
rm -rf xsim.dir xvlog.log xvlog.pb xelab.log xelab.pb 2>/dev/null || true

# ------------------------------------------------------------------
# Step 1: Compile (xvlog) - use -sv for SystemVerilog support
# ------------------------------------------------------------------
echo "========================================"
echo " Step 1: xvlog (analysis)"
echo "========================================"

"$VIVADO_BIN/xvlog" -sv \
    "$SRC_DIR/dff.v" \
    "$SRC_DIR/dff_en.v" \
    "$SRC_DIR/mux2x1.v" \
    "$SRC_DIR/carry_lookahead_adder.v" \
    "$SRC_DIR/wallace_tree_multiplier.v" \
    "$SRC_DIR/signed_seq_multiplier.v" \
    "$SRC_DIR/truncator.v" \
    "$SRC_DIR/clk_gating.v" \
    "$SRC_DIR/zero_skipping.v" \
    "$SRC_DIR/ifmap_spad.v" \
    "$SRC_DIR/filter_spad.v" \
    "$SRC_DIR/psum_spad.v" \
    "$SRC_DIR/fifo_flag_generator.v" \
    "$SRC_DIR/fifo_up_down_counter.v" \
    "$SRC_DIR/fifo_rd_ctrl.v" \
    "$SRC_DIR/fifo_wr_ctrl.v" \
    "$SRC_DIR/fifo_mem.v" \
    "$SRC_DIR/fifo_top.v" \
    "$SRC_DIR/fifo_wrapper.v" \
    "$SRC_DIR/pe_ctrl.sv" \
    "$SRC_DIR/pe.v" \
    "$SRC_DIR/pe_wrapper.v" \
    "$SIM_DIR/PE_tb.sv"

echo "xvlog: OK"
echo ""

# ------------------------------------------------------------------
# Step 2: Elaborate (xelab) - use -timescale to avoid mismatch errors
# ------------------------------------------------------------------
echo "========================================"
echo " Step 2: xelab (elaboration)"
echo "========================================"

"$VIVADO_BIN/xelab" -L xil_defaultlib -s pe_sim -timescale 1ns/1ps PE_tb

echo "xelab: OK"
echo ""

# ------------------------------------------------------------------
# Step 3: Simulate (xsim)
# ------------------------------------------------------------------
echo "========================================"
echo " Step 3: xsim (simulation)"
echo "========================================"

# Use a Tcl script for reliable batch mode execution
cat > run_xsim.tcl << 'TCL_EOF'
run -all
quit
TCL_EOF

"$VIVADO_BIN/xsim" pe_sim --tclbatch run_xsim.tcl

rm -f run_xsim.tcl

echo ""
echo "========================================"
echo " Simulation complete."
echo "========================================"
