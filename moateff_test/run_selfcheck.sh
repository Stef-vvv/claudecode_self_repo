#!/bin/bash
VIVADO="E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin"
cd "H:/moateff_test"
echo "=== Compiling selfcheck testbench ==="
"$VIVADO/xvlog" -sv sim/tb_selfcheck.sv
if [ $? -ne 0 ]; then echo "TB compile failed"; exit 1; fi
echo "=== Elaborating ==="
"$VIVADO/xelab" -timescale 1ns/1ps -L xil_defaultlib -s selfcheck_sim tb_selfcheck
if [ $? -ne 0 ]; then echo "Elab failed"; exit 1; fi
echo "=== Running ==="
"$VIVADO/xsim" selfcheck_sim -R
