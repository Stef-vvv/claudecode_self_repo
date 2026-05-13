#!/bin/bash
VIVADO="E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin"
cd "H:/moateff_test"

echo "=== Step 1: xvlog — Packages ==="
"$VIVADO/xvlog" -sv \
  sim/shared_pkg.sv \
  sim/file_pkg.sv \
  sim/fifo_if_pkg.sv \
  sim/glb_pkg.sv \
  sim/cfg_pkg.sv \
  sim/load_pkg.sv \
  sim/layer_pkg.sv \
  sim/test_pkg.sv
if [ $? -ne 0 ]; then echo "PACKAGES FAILED"; exit 1; fi
echo "Packages OK"

echo "=== Step 2: xvlog — RTL Sources ==="
# Use null-separated find + bash array to handle spaces in paths
RTL_FILES=()
while IFS= read -r -d '' f; do
  RTL_FILES+=("$f")
done < <(find src \( -name "*.sv" -o -name "*.v" \) -print0 | sort -z)

echo "Compiling ${#RTL_FILES[@]} RTL files..."
"$VIVADO/xvlog" -sv "${RTL_FILES[@]}"
if [ $? -ne 0 ]; then echo "RTL FAILED"; exit 1; fi
echo "RTL OK"

echo "=== Step 3: xvlog — Testbench ==="
"$VIVADO/xvlog" -sv sim/Eyeriss_tb.sv
if [ $? -ne 0 ]; then echo "TB FAILED"; exit 1; fi
echo "Testbench OK"

echo "=== Step 4: xelab ==="
"$VIVADO/xelab" -L xil_defaultlib -s eyeriss_sim eyeriss_tb
if [ $? -ne 0 ]; then echo "ELAB FAILED"; exit 1; fi
echo "=== COMPILATION SUCCESSFUL ==="
