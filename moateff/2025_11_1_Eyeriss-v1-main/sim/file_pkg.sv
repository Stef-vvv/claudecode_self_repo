package file_pkg;
import shared_pkg::*;
    
    // compare_files(filename1, filename2, num_words);

    task compare_files(
        input string filename1, 
        input string filename2, 
        input int num_words
    );
        int file1, file2, logfile;
        string line1, line2;
        string word1, word2;
        automatic int lineno = 0;
    
        shared_pkg::error_count = 0;
        shared_pkg::pass_count = 0; 
    
        file1 = $fopen(filename1, "r");
        file2 = $fopen(filename2, "r");
        logfile = $fopen(".../log.txt", "w");
    
        if (file1 == 0 || file2 == 0) begin
            $display("[ERROR] Could not open one or both files.");
            $fdisplay(logfile, "[ERROR] Could not open one or both files.");
            $fclose(logfile);
            $stop;
        end
    
        while (lineno < num_words) begin
            void'($fgets(line1, file1));
            void'($fgets(line2, file2));
            lineno++;
    
            void'($sscanf(line1, "%s", word1));
            void'($sscanf(line2, "%s", word2));
    
            if (word1 != word2) begin
                $display("[Mismatch] at line %0d:  OUTPUT  = %s,  EXPECTED = %s", lineno, word1, word2);
                $fdisplay(logfile, "[Mismatch] at line %0d:  OUTPUT  = %s,  EXPECTED = %s", lineno, word1, word2);
                shared_pkg::error_count++;
            end else begin
                $display("[Match] at line %0d:  OUTPUT  = %s,  EXPECTED = %s", lineno, word1, word2);
                $fdisplay(logfile, "[Match] at line %0d:  OUTPUT  = %s,  EXPECTED = %s", lineno, word1, word2);
                shared_pkg::pass_count++;
            end
        end
    
        if (lineno < num_words) begin
            $display("[ERROR] One file ended before %0d lines.", num_words);
            $fdisplay(logfile, "[ERROR] One file ended before %0d lines.", num_words);
        end 
    
        $display("Mismatch Count = %0d, Match Count = %0d", shared_pkg::error_count, shared_pkg::pass_count);
        $fdisplay(logfile, "Mismatch Count = %0d, Match Count = %0d", shared_pkg::error_count, shared_pkg::pass_count);
    
        $fclose(file1);
        $fclose(file2);
        $fclose(logfile);
    endtask

endpackage : file_pkg