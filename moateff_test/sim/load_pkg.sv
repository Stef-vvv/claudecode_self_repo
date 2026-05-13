package load_pkg;
import shared_pkg::*;
import fifo_if_pkg::*;
    
//    task conv1_load_data_seg1();
//        conv1_load_filter();
//        wait_core_cycle(1);
                
//        conv1_load_bias();
//        wait_core_cycle(1); 
        
//        conv1_load_ifmap_part1();
//        wait_core_cycle(1);
//    endtask
    
//    task conv1_load_data_seg2();
//        conv1_load_ifmap_part2();
//        wait_core_cycle(1);
//    endtask
    
//    task conv1_load_data_seg3();
//        conv1_load_ifmap_part3();
//        wait_core_cycle(1);
//    endtask
    
//    task conv1_load_data_seg4();
//        conv1_load_ifmap_part4();
//        wait_core_cycle(1);
//    endtask
    
//    task conv1_load_data_seg5();
//        conv1_load_ifmap_part5();
//        wait_core_cycle(1);
//    endtask
    
//    task conv1_load_data_seg6();
//        conv1_load_ifmap_part6();
//        wait_core_cycle(1);
//    endtask
    
//    task conv1_load_data_seg7();
//        conv1_load_ifmap_part7();
//        wait_core_cycle(1);
//    endtask
    
//    task conv1_load_data_seg8();
//        conv1_load_ifmap_part8();
//        wait_core_cycle(1);
//    endtask
    
//    task conv2_load_data();
//        conv2_load_filter();
//        wait_core_cycle(1);
                
//        conv2_load_bias();
//        wait_core_cycle(1); 
//    endtask
    
//    task conv3_load_data();
//        conv3_load_filter();
//        wait_core_cycle(1);
                
//        conv3_load_bias();
//        wait_core_cycle(1); 
//    endtask
    
//    task conv4_load_data();
//        conv4_load_filter();
//        wait_core_cycle(1);
                
//        conv4_load_bias();
//        wait_core_cycle(1); 
//    endtask
    
//    task conv5_load_data();
//        conv5_load_filter();
//        wait_core_cycle(1);
                
//        conv5_load_bias();
//        wait_core_cycle(1); 
//    endtask
    
//    task conv1_load_ifmap_part1();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv1/ifmap/conv1_ifmap_seg1_64.txt";
//        data_type = IFMAP;
//        base_addr = 0;
//        num_words = (CONV1_D * CONV1_W * CONV1_C * CONV1_N + 1) / 4; 
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask
    
//    task conv1_load_ifmap_part2();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv1/ifmap/conv1_ifmap_seg2_64.txt";
//        data_type = IFMAP;
//        base_addr = 0;
//        num_words = (CONV1_D * CONV1_W * CONV1_C * CONV1_N + 1) / 4; 
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask
    
//    task conv1_load_ifmap_part3();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv1/ifmap/conv1_ifmap_seg3_64.txt";
//        data_type = IFMAP;
//        base_addr = 0;
//        num_words = (CONV1_D * CONV1_W * CONV1_C * CONV1_N + 1) / 4; 
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask
    
//    task conv1_load_ifmap_part4();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv1/ifmap/conv1_ifmap_seg4_64.txt";
//        data_type = IFMAP;
//        base_addr = 0;
//        num_words = (CONV1_D * CONV1_W * CONV1_C * CONV1_N + 1) / 4; 
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask
    
//    task conv1_load_ifmap_part5();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv1/ifmap/conv1_ifmap_seg5_64.txt";
//        data_type = IFMAP;
//        base_addr = 0;
//        num_words = (CONV1_D * CONV1_W * CONV1_C * CONV1_N + 1) / 4; 
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask
    
//    task conv1_load_ifmap_part6();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv1/ifmap/conv1_ifmap_seg6_64.txt";
//        data_type = IFMAP;
//        base_addr = 0;
//        num_words = (CONV1_D * CONV1_W * CONV1_C * CONV1_N + 1) / 4; 
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask
    
//    task conv1_load_ifmap_part7();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv1/ifmap/conv1_ifmap_seg7_64.txt";
//        data_type = IFMAP;
//        base_addr = 0;
//        num_words = (CONV1_D * CONV1_W * CONV1_C * CONV1_N + 1) / 4; 
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask
    
//    task conv1_load_ifmap_part8();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv1/ifmap/conv1_ifmap_seg8_64.txt";
//        data_type = IFMAP;
//        base_addr = 0;
//        num_words = (CONV1_D * CONV1_W * CONV1_C * CONV1_N + 1) / 4; 
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask
                
//    task conv1_load_bias();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv1/bias/conv1_bias_64.txt";
//        data_type = BIAS;
//        base_addr = 0;
//        num_words = CONV1_M / 4;
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask 
    
//    task conv1_load_filter();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv1/filter/conv1_filter_64.txt";
//        data_type = FILTER;
//        base_addr = 0;
//        num_words = (CONV1_R * CONV1_S * CONV1_C * CONV1_M) / 4;
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask
    
//    task conv2_load_bias();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv2/bias/conv2_bias_64.txt";
//        data_type = BIAS;
//        base_addr = 0;
//        num_words = CONV2_M / 4;
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask 
    
//    task conv2_load_filter();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv2/filter/conv2_filter_64.txt";
//        data_type = FILTER;
//        base_addr = 0;
//        num_words = (CONV2_R * CONV2_S * CONV2_C * CONV2_M) / 4; 
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask
    
//    task conv3_load_bias();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv3/bias/conv3_bias_64.txt";
//        data_type = BIAS;
//        base_addr = 0;
//        num_words = CONV3_M / 4;
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask 
    
//    task conv3_load_filter();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv3/filter/conv3_filter_64.txt";
//        data_type = FILTER;
//        base_addr = 0;
//        num_words = (CONV3_R * CONV3_S * CONV3_C * CONV3_M) / 4; 
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask
    
//    task conv4_load_bias();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv4/bias/conv4_bias_64.txt";
//        data_type = BIAS;
//        base_addr = 0;
//        num_words = CONV4_M / 4;
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask 
    
//    task conv4_load_filter();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv4/filter/conv4_filter_64.txt";
//        data_type = FILTER;
//        base_addr = 0;
//        num_words = (CONV4_R * CONV4_S * CONV4_C * CONV4_M) / 4; 
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask
    
//    task conv5_load_bias();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv5/bias/conv5_bias_64.txt";
//        data_type = BIAS;
//        base_addr = 0;
//        num_words = CONV5_M / 4;
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask 
    
//    task conv5_load_filter();
//        string filename;
//        bit [ADDR_WIDTH-1:0] base_addr;
//        bit [ADDR_WIDTH-1:0] num_words;
//        data_t data_type;
        
//        filename = "D:/data/Graduation Project/GP_AlexNet/Results/Conv5/filter/conv5_filter_64.txt";
//        data_type = FILTER;
//        base_addr = 0;
//        num_words = (CONV5_R * CONV5_S * CONV5_C * CONV5_M) / 4; 
        
//        write_data_from_dram_to_glb(data_type, filename, base_addr, num_words);
//    endtask
    
endpackage : load_pkg