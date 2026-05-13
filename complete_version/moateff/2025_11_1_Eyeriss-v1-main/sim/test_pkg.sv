package test_pkg;
import shared_pkg::*;
import layer_pkg::*;
    
    task run_test();
        initialize_dut();        
        wait_core_cycle(1);
        assert_reset();
        wait_core_cycle(1);
        run_conv1();
        wait_core_cycle(1);
//        run_conv2();       
//        wait_core_cycle(1);
//        run_conv3();
//        wait_core_cycle(1);
//        run_conv4();        
//        wait_core_cycle(1);
//        run_conv5();
//        wait_core_cycle(1);
    endtask 
    
endpackage
