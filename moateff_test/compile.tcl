# Vivado 2020.2 compile script for Eyeriss v1
set root_dir "H:/moateff_test"

# Step 1: Compile packages (order matters for dependencies)
set pkg_dir "$root_dir/sim"
xvlog -sv \
  "$pkg_dir/shared_pkg.sv" \
  "$pkg_dir/file_pkg.sv" \
  "$pkg_dir/fifo_if_pkg.sv" \
  "$pkg_dir/glb_pkg.sv" \
  "$pkg_dir/cfg_pkg.sv" \
  "$pkg_dir/load_pkg.sv" \
  "$pkg_dir/layer_pkg.sv" \
  "$pkg_dir/test_pkg.sv"
puts "Packages compiled OK"

# Step 2: Compile all RTL sources
set src_dir "$root_dir/src"
set rtl_files [glob -nocomplain -directory $src_dir *.sv *.v]
# Also find in subdirectories
foreach subdir [glob -nocomplain -directory $src_dir -types d *] {
  set rtl_files [concat $rtl_files [glob -nocomplain -directory $subdir *.sv *.v]]
  foreach subsubdir [glob -nocomplain -directory $subdir -types d *] {
    set rtl_files [concat $rtl_files [glob -nocomplain -directory $subsubdir *.sv *.v]]
    foreach subsubsubdir [glob -nocomplain -directory $subsubdir -types d *] {
      set rtl_files [concat $rtl_files [glob -nocomplain -directory $subsubsubdir *.sv *.v]]
    }
  }
}
# Filter out non-existent files
set rtl_files [lsort -unique $rtl_files]
puts "Compiling [llength $rtl_files] RTL source files..."
foreach f $rtl_files {
  puts "  $f"
}
xvlog -sv {*}$rtl_files
puts "RTL compiled OK"

# Step 3: Compile testbench
xvlog -sv "$pkg_dir/Eyeriss_tb.sv"
puts "Testbench compiled OK"

# Step 4: Elaborate
xelab -L xil_defaultlib -s eyeriss_sim eyeriss_tb
puts "Elaboration OK"

puts "=== COMPILATION SUCCESSFUL ==="
puts "Run: xsim eyeriss_sim -R"
