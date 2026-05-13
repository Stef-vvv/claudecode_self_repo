# Run eyeriss simulation for limited time and report key signals
run 1000ns
puts "Simulation running..."
puts "Time: [current_time]"
run 10000ns
puts "Time: [current_time]"
run 50000ns
puts "Time: [current_time]"
run 100000ns
puts "Time: [current_time]"
quit
