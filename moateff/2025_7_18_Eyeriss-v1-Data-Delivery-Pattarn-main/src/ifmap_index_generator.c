#include <stdio.h>

// Function prototypes
void ifmapAddressGenerator(FILE *ifmap_index_file, FILE *ifmap_address_file, int ****Ifmap, 
                        int W, int H, int n, int q, int r, int ifmap_start, int channel_start, int pass_num);
int calculateAddress(int ****Array, int n, int c, int h, int w);

void ifmapAddressGenerator(FILE *ifmap_index_file, FILE *ifmap_address_file, int ****Ifmap, 
                        int W, int H, int n, int q, int r, int ifmap_start, int channel_start, int pass_num) {
    
    int ifmap_index, channel_index, row_index, col_index;
    static int cycle_count = 1;
    
    fprintf(ifmap_index_file, "\nprocessing pass %d:\n", pass_num);

    for (int n_ind = 0; n_ind < n; n_ind++){
        for (int W_ind = 0; W_ind < W; W_ind++){
            for (int q_ind = 0; q_ind < q; q_ind++){
                for (int H_ind = 0; H_ind < H; H_ind++){
                    for (int r_ind = 0; r_ind < r; r_ind++){

                        ifmap_index   = ifmap_start + n_ind;
                        channel_index = channel_start + q_ind + r_ind * q;
                        row_index     = H_ind;
                        col_index     = W_ind;
                        
                        fprintf(ifmap_index_file, "cycle  %d: ifmap %d, channel %d, row %d, col %d, address: %d\n", 
                                cycle_count++, ifmap_index, channel_index, row_index, col_index,
                                calculateAddress(Ifmap, ifmap_index, channel_index, row_index, col_index));
                        fprintf(ifmap_address_file, "%d\n", calculateAddress(Ifmap, ifmap_index, channel_index, row_index, col_index));

                    }
                }
            }
        }
    }
}