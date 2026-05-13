#include <stdio.h>

// Function prototypes
void psumAddressGenerator(FILE *psum_index_file, FILE *psum_address_file, int **** Psum,
                            int F, int E, int n, int p, int t, int psum_start, int channel_start, int pass_num);
int calculateAddress(int ****Array, int n, int c, int h, int w);

void psumAddressGenerator(FILE *psum_index_file, FILE *psum_address_file, int **** Psum,
                            int F, int E, int n, int p, int t, int psum_start, int channel_start, int pass_num) {
    
    int psum_index, channel_index, row_index, col_index;
    static int cycle_count = 1;

    fprintf(psum_index_file, "\nprocessing pass %d:\n", pass_num);
    
    int n_ind = 0, p_ind = 0, F_ind = 0;
	int n_reg = 0, p_reg = 0, F_reg = 0;

    while(!((n_reg == n - 1) & (p_reg == p - 1) & (F_reg == F - 1))){
        
        for (int E_ind = 0; E_ind < E ; E_ind++){
            for (int t_ind = 0; t_ind < t; t_ind++){

                n_ind = n_reg;
                p_ind = p_reg;
                F_ind = F_reg;

                for(int i = 0; i < 4; i++){
                    
                    psum_index    = psum_start + n_ind;
                    channel_index = channel_start + p_ind + (t_ind * p);
                    row_index     = E_ind;
                    col_index     = F_ind;
                    
                    fprintf(psum_index_file, "cycle  %d: psum %d, channel %d, row %d, col %d, address: %d\n", 
                            cycle_count++, psum_index, channel_index, row_index, col_index,
                            calculateAddress(Psum, psum_index, channel_index, row_index, col_index));
                    fprintf(psum_address_file, "%d\n", calculateAddress(Psum, psum_index, channel_index, row_index, col_index));
                    // fprintf(psum_index_file, "n_ind = %d, p_ind = %d, F_ind = %d\n", n_ind, p_ind, F_ind);

                    if (p_ind == p - 1){
                        p_ind = 0;
                        if (F_ind == F - 1){
                            F_ind = 0;
                            if (n_ind == n - 1){
                                p_ind = p - 1;
                                F_ind = F - 1;
                                n_ind = n - 1;
                            } else {n_ind++;}
                        } else {F_ind++;}
                    } else {p_ind++;}

                }
            }
        }

        n_reg = n_ind;
        p_reg = p_ind;
        F_reg = F_ind;
        // fprintf(psum_index_file, "n_reg = %d, p_reg = %d, F_reg = %d\n\n", n_reg, p_reg, F_reg);

    }
}

/*
for (int n_ind = 0; n_ind < n ; n_ind++){
    for (int F_ind = 0; F_ind < F ; F_ind++){
        for (int p_ind = 0; p_ind < p; p_ind+=4){
        }
    }
}
*/