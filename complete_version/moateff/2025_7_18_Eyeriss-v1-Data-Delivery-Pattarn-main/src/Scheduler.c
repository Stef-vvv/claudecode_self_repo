#include <stdio.h>

// Function prototypes
void scheduler(int M, int C, int N, int n, int p, int q, int r, int t);

void scheduler(int M, int C, int N, int n, int p, int q, int r, int t) {
    FILE *file = fopen("scheduler.txt", "w");
    if (file == NULL) {
        printf("Error opening file!\n");
        return;
    }
    
    int filter_start, filter_end, channel_start, channel_end, ifmap_start, ifmap_end;
    int pass_num = 0;

    for (int N_ind = 0; N_ind < N; N_ind+=n) {
        for (int C_ind = 0; C_ind < C; C_ind+=(q*r)) {
            for (int M_ind = 0; M_ind < M; M_ind+=(p*t)) {

                filter_start  = M_ind;
                filter_end    = M_ind + p * t;
                channel_start = C_ind; 
                channel_end   = C_ind + q * r;
                ifmap_start   = N_ind;
                ifmap_end     = N_ind + n;

                fprintf(file, "processing pass %d: ", pass_num++);
                fprintf(file, "filter ids: %d-%d, ", filter_start, filter_end - 1);
                fprintf(file, "channel ids: %d-%d, ", channel_start, channel_end - 1);
                fprintf(file, "ifmap ids: %d-%d\n", ifmap_start, ifmap_end - 1);
            }
        }
    }
    fprintf(file, "processing passes are done\n");
    fclose(file);
}
