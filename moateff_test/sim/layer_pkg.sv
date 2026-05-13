package layer_pkg;
import shared_pkg::*;
import cfg_pkg::*;
import load_pkg::*;
    
    task run_conv1();
        conv1_cfg();
        
        shared_pkg::start = 1'b1;
        wait_core_cycle(1);
        shared_pkg::start = 1'b0;
        
        shared_pkg::start_pass = 1'b1;
        wait(shared_pkg::ofmap_dump);
        shared_pkg::dump_done = 1'b1;
        
        wait(shared_pkg::done);
    endtask
    
    task run_conv2();
        conv2_cfg();
    endtask
    
    task run_conv3();
        conv3_cfg();
    endtask
    
    task run_conv4();
        conv4_cfg();
    endtask
    
    task run_conv5();
        conv5_cfg();
    endtask
    
endpackage : layer_pkg
