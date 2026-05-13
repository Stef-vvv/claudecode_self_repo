#include <stdio.h>

// Function prototypes
void filterAddressGenerator(FILE *filter_index_file, FILE *filter_address_file, int **** Filter,
                            int S, int R, int p, int q, int r, int t, int filter_start, int channel_start, int pass_num);
int calculateAddress(int ****Array, int n, int c, int h, int w);

void filterAddressGenerator(FILE *filter_index_file, FILE *filter_address_file, int **** Filter,
                            int S, int R, int p, int q, int r, int t, int filter_start, int channel_start, int pass_num) {
    
    int filter_index, channel_index, row_index, col_index;
    static int cycle_count = 1;
    
    fprintf(filter_index_file, "\nprocessing pass %d:\n", pass_num);
    
    int p_ind = 0, q_ind = 0, S_ind = 0;
	int p_reg = 0, q_reg = 0, S_reg = 0;
        
	while(!((p_reg == p - 1) & (q_reg == q - 1) & (S_reg == S -1))){

		for (int R_ind = 0; R_ind < R ; R_ind++){
			for (int r_ind = 0; r_ind < r; r_ind++){
				for (int t_ind = 0; t_ind < t; t_ind++){

					p_ind = p_reg;	
					q_ind = q_reg; 
					S_ind = S_reg;

					for(int i = 0; i < 4; i++){

						filter_index  = filter_start + p_ind + (t_ind * p);
                        channel_index = channel_start + q_ind + (r_ind * q);
                        row_index     = R_ind;
                        col_index     = S_ind;
						
						fprintf(filter_index_file, "cycle  %d: filter %d, channel %d, row %d, col %d, address: %d\n", 
								cycle_count++, filter_index, channel_index, row_index, col_index,
								calculateAddress(Filter, filter_index, channel_index, row_index, col_index));
						fprintf(filter_address_file, "%d\n", calculateAddress(Filter, filter_index, channel_index, row_index, col_index));
						// fprintf(filter_index_file, "p_ind = %d, q_ind = %d, S_ind = %d\n", p_ind, q_ind, S_ind);
						
						if (p_ind == p - 1){
							p_ind = 0;
							if (q_ind == q - 1){
								q_ind = 0;
								if (S_ind == S - 1){
									p_ind = p - 1;
									q_ind = q - 1;
									S_ind = S - 1;
								} else {S_ind++;}
							} else {q_ind++;}
						} else {p_ind++;}
					}
                }
            }
        }

		p_reg = p_ind;	
		q_reg = q_ind; 
		S_reg = S_ind;
		// fprintf(filter_index_file, "p_reg = %d, q_reg = %d, S_reg = %d\n\n", p_reg, q_reg, S_reg);
	}
}

/*
    for (int S_ind = 0; S_ind < S ; S_ind++){
        for (int q_ind = 0; q_ind < q; q_ind++){
            for (int p_ind = 0; p_ind < p; p_ind++){
	    	}
	 	}
    }
*/