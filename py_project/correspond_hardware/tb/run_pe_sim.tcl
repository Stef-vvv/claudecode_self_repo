# Vivado simulation script for PE module
# Usage: cd correspond_hardware/tb && vivado -mode batch -source run_pe_sim.tcl

set VivadoBin "E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin"

# Compile
exec ${VivadoBin}/xvlog ../rtl/pe.v pe_tb.v

# Elaborate
exec ${VivadoBin}/xelab -L xil_defaultlib -s pe_sim pe_tb

# Simulate
exec ${VivadoBin}/xsim pe_sim -R

puts "PE simulation done."
