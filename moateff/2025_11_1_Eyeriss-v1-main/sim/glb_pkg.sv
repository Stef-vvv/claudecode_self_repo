package glb_pkg;
import shared_pkg::*;

//    string filename1, filename2;
//    bit [ADDR_WIDTH-1:0] base_addr;
//    bit [ADDR_WIDTH-1:0] num_words;
//    data_t data_type;

//    filename1 = ".../filename.txt";
//    data_type = IFMAP;
//    base_addr = 0;
//    num_words = 43200;
//    write_data_to_glb(data_type, filename1, base_addr, num_words);    

//    filename1 = ".../filename.txt";
//    data_type = PSUM;
//    base_addr = 0;
//    num_words = 64896;
//    read_data_from_glb(data_type, filename1, base_addr, num_words);
    
//    task read_data_from_glb(
//        input bit [1:0] glb_name,
//        input string filename,
//        input bit [ADDR_WIDTH-1:0] base_addr,
//        input bit [ADDR_WIDTH-1:0] words_num
//    );
//        int file;
//        logic [DATA_WIDTH-1:0] word;
//        bit   [ADDR_WIDTH-1:0] addr;
        
//        file = $fopen(filename, "w");
//        if (file == 0) begin
//            $display("[ERROR] Could not open file %s", filename);
//            return;
//        end
    
//        for (int i = 0; i < words_num; i++) begin
//            addr = base_addr + i;
            
//            case (glb_name)
//                IFMAP: begin
//                    case (addr[1:0])
//                        2'b00: word = DUT.GLB.U1_IFMAP.U0_0.mem[addr/4];
//                        2'b01: word = DUT.GLB.U1_IFMAP.U0_1.mem[addr/4];
//                        2'b10: word = DUT.GLB.U1_IFMAP.U1_0.mem[addr/4];
//                        2'b11: word = DUT.GLB.U1_IFMAP.U1_1.mem[addr/4];
//                    endcase
//                end 
//                FILTER: begin
//                    case (addr[1:0])
//                        2'b00: word = DUT.GLB.U2_FILTER.U0_0.mem[addr/4];
//                        2'b01: word = DUT.GLB.U2_FILTER.U0_1.mem[addr/4];
//                        2'b10: word = DUT.GLB.U2_FILTER.U1_0.mem[addr/4];
//                        2'b11: word = DUT.GLB.U2_FILTER.U1_1.mem[addr/4];
//                    endcase
//                end 
//                BIAS: begin
//                    case (addr[1:0])
//                        2'b00: word = DUT.GLB.U3_BIAS.U0_0.mem[addr/4];
//                        2'b01: word = DUT.GLB.U3_BIAS.U0_1.mem[addr/4];
//                        2'b10: word = DUT.GLB.U3_BIAS.U1_0.mem[addr/4];
//                        2'b11: word = DUT.GLB.U3_BIAS.U1_1.mem[addr/4];
//                    endcase
//                end 
//                PSUM: begin
//                    case (addr[1:0])
//                        2'b00: word = DUT.GLB.U4_PSUM.U0_0.mem[addr/4];
//                        2'b01: word = DUT.GLB.U4_PSUM.U0_1.mem[addr/4];
//                        2'b10: word = DUT.GLB.U4_PSUM.U1_0.mem[addr/4];
//                        2'b11: word = DUT.GLB.U4_PSUM.U1_1.mem[addr/4];
//                    endcase
//                end 
//            endcase
                
//            $fwrite(file, "%b\n", word);
//        end
   
//        $fclose(file);
//    endtask
    
//    task write_data_to_glb(
//        input bit [1:0] glb_name,
//        input string filename,
//        input bit [ADDR_WIDTH-1:0] base_addr,
//        input bit [ADDR_WIDTH-1:0] words_num
//    );
//        int file;
//        logic [DATA_WIDTH-1:0] word;
//        bit   [ADDR_WIDTH-1:0] addr;
    
//        file = $fopen(filename, "r");
//        if (file == 0) begin
//            $display("[ERROR] Could not open file %s", filename);
//            return;
//        end
    
//        for (int i = 0; i < words_num; i++) begin
//            addr = base_addr + i;
    
//            if ($feof(file)) begin
//                $display("[WARNING] Reached EOF before expected word count at line %0d", i);
//                break;
//            end
    
//            void'($fscanf(file, "%b\n", word));
    
//            case (glb_name)
//                IFMAP: begin
//                    case (addr[1:0])
//                        2'b00: DUT.GLB.U1_IFMAP.U0_0.mem[addr/4] = word;
//                        2'b01: DUT.GLB.U1_IFMAP.U0_1.mem[addr/4] = word;
//                        2'b10: DUT.GLB.U1_IFMAP.U1_0.mem[addr/4] = word;
//                        2'b11: DUT.GLB.U1_IFMAP.U1_1.mem[addr/4] = word;
//                    endcase
//                end
//                FILTER: begin
//                    case (addr[1:0])
//                        2'b00: DUT.GLB.U2_FILTER.U0_0.mem[addr/4] = word;
//                        2'b01: DUT.GLB.U2_FILTER.U0_1.mem[addr/4] = word;
//                        2'b10: DUT.GLB.U2_FILTER.U1_0.mem[addr/4] = word;
//                        2'b11: DUT.GLB.U2_FILTER.U1_1.mem[addr/4] = word;
//                    endcase
//                end
//                BIAS: begin
//                    case (addr[1:0])
//                        2'b00: DUT.GLB.U3_BIAS.U0_0.mem[addr/4] = word;
//                        2'b01: DUT.GLB.U3_BIAS.U0_1.mem[addr/4] = word;
//                        2'b10: DUT.GLB.U3_BIAS.U1_0.mem[addr/4] = word;
//                        2'b11: DUT.GLB.U3_BIAS.U1_1.mem[addr/4] = word;
//                    endcase
//                end
//                PSUM: begin
//                    case (addr[1:0])
//                        2'b00: DUT.GLB.U4_PSUM.U0_0.mem[addr/4] = word;
//                        2'b01: DUT.GLB.U4_PSUM.U0_1.mem[addr/4] = word;
//                        2'b10: DUT.GLB.U4_PSUM.U1_0.mem[addr/4] = word;
//                        2'b11: DUT.GLB.U4_PSUM.U1_1.mem[addr/4] = word;
//                    endcase
//                end
//            endcase
//        end
    
//        $fclose(file);
//    endtask

endpackage : glb_pkg