package cfg_pkg;
import shared_pkg::*;
    
    task conv1_cfg();
        string filename;
        filename = "E:/data/Digital-IC/Git/Eyeriss-v1/cfg/conv1/serial_data.txt";
        cfg_scan_chain(filename);
    endtask
    
    task conv2_cfg();
        string filename;
        filename = "E:/data/Digital-IC/Git/Eyeriss-v1/cfg/conv2/serial_data.txt";
        cfg_scan_chain(filename);
    endtask
    
    task conv3_cfg();
        string filename;
        filename = "E:/data/Digital-IC/Git/Eyeriss-v1/cfg/conv3/serial_data.txt";
        cfg_scan_chain(filename);
    endtask
    
    task conv4_cfg();
        string filename;
        filename = "E:/data/Digital-IC/Git/Eyeriss-v1/cfg/conv4/serial_data.txt";
        cfg_scan_chain(filename);
    endtask
    
    task conv5_cfg();
        string filename;
        filename = "E:/data/Digital-IC/Git/Eyeriss-v1/cfg/conv5/serial_data.txt";
        cfg_scan_chain(filename);
    endtask
    
    task cfg_scan_chain(
        input string filename
    );
        int file;
        int char_val;
        int bit_val;
        string line;

        file = $fopen(filename, "r");
        if (file == 0) begin
            $display("[ERROR] Could not open file: %s", filename);
            $stop;
        end

        shared_pkg::scan_en = 1;

        while (!$feof(file)) begin
            line = "";
            void'($fgets(line, file));
            if (line.len() > 0) begin
            $sscanf(line, "%d", bit_val);
            shared_pkg::scan_in = bit_val;
            wait_core_cycle(1);
            end
        end

        shared_pkg::scan_en = 0;
        $fclose(file);

    endtask

endpackage : cfg_pkg