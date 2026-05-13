package fifo_if_pkg;
import shared_pkg::*;
import file_pkg::*;
    	
    task write_data_from_dram_to_glb(
		input bit [1:0] transfer_type_t,
        input string filename,
        input bit [ADDR_WIDTH-1:0] base_addr_t,
        input bit [ADDR_WIDTH-1:0] words_num_t
	);
        int i; 
        int file;
        bit [FIFO_WIDTH-1:0] word;
        wait_core_cycle(1);

        shared_pkg::words_num = words_num_t;
        shared_pkg::transfer_type = transfer_type_t;
        
        shared_pkg::start_forward = 1;
        wait_core_cycle(1);
        shared_pkg::start_forward = 0;
        
        wait_link_cycle(1);
        
        file = $fopen(filename, "r");
        if (file == 0) begin
            $display("[ERROR] Could not open file: %s", filename);
            $stop;
        end
        
        for (i = 0; i < words_num_t; i = i + 1) begin
            wait(shared_pkg::re_from_dram);
            wait_link_cycle(1);
            $fscanf(file, "%b\n", word);
            shared_pkg::rdata_from_dram = word;
            shared_pkg::valid_from_dram = 1;
        end

        wait_link_cycle(1);
        shared_pkg::rdata_from_dram = 0;
        shared_pkg::valid_from_dram = 0;
        
        $fclose(file);
        wait(shared_pkg::transfer_done);
    endtask
	
	/*
    task write_data_from_glb_to_dram(
		input string file_path,
        input [ADDR_WIDTH-1:0] base_addr,
        input [ADDR_WIDTH-1:0] num_words
	);
		int i, file;
        @(posedge core_clk);

        base_address = base_addr;
        words_num = num_words;

        start_backward = 1;
        @(posedge core_clk);
        start_backward = 0;

		file  = $fopen(file_path, "w");
		
		for (i = 0; i < num_words; i = i + 1) begin
            @(posedge link_clk);
			wait(we_to_dram);
			$fwrite(file, "%b\n", wdata_to_dram);
        end

		$fclose(file);

        wait (shared_pkg::transfer_done);
    endtask
	*/
	     
endpackage : fifo_if_pkg
