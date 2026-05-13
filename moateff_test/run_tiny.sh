#!/bin/bash
VIVADO="E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin"
cd "H:/moateff_test"
echo "=== Compiling tiny test ==="
"$VIVADO/xvlog" -sv sim/tb_tiny_test.sv 2>&1 | grep -E "ERROR|WARNING|INFO.*Analyzing"
echo "=== Elaborating ==="
"$VIVADO/xelab" -timescale 1ns/1ps -L xil_defaultlib -s tiny_sim tb_tiny_test 2>&1 | grep -E "ERROR|Built|fail"
echo "=== Running (60s timeout) ==="
timeout 60 "$VIVADO/xsim" tiny_sim -R 2>&1
