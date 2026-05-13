#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "Scheduler.c"
#include "Array.c"
#include "ifmap_index_generator.c"
#include "filter_index_generator.c"
#include "psum_index_generator.c"

// Function prototypes
void getParametersFromFile(const char* filename, int* M, int* C, int* N, int* W, 
                    int* H, int* R, int* S, int* E, int*F, int* n, int* p, int* q, int* r, int* t);
int ****allocateContiguousArray(int N, int C, int H, int W);
void freeContiguousArray(int ****Array, int N, int C);
int calculateAddress(int ****Array, int n, int c, int h, int w);
void indexAddressGenerator(int ****Ifmap, int ****Filter, int **** Psum, int M, int C, int N, int W, int H,
                int R, int S, int E, int F, int n, int p, int q, int r, int t);
void ifmapAddressGenerator(FILE *ifmap_index_file, FILE *ifmap_address_file, int ****Ifmap, 
    int W, int H, int n, int q, int r, int ifmap_start, int channel_start, int pass_num);
void filterAddressGenerator(FILE *filter_index_file, FILE *filter_address_file, int **** Filter,
    int S, int R, int p, int q, int r, int t, int filter_start, int channel_start, int pass_num);
void psumAddressGenerator(FILE *psum_index_file, FILE *psum_address_file, int **** Psum,
    int F, int E, int n, int p, int t, int psum_start, int channel_start, int pass_num);
void clearFile(const char* filename);

int main() {
    int M, C, N, W, H, R, S, E, F, n, p, q, r, t;
    getParametersFromFile("parameter.txt", &M, &C, &N, &W, &H, &R, &S, &E, &F, &n, &p, &q, &r, &t);
    scheduler(M, C, N, n, p, q, r, t);

    int ****Ifmap = allocateContiguousArray(N, C, H, W);
    int ****Filter = allocateContiguousArray(M, C, R, S);
    int ****Psum = allocateContiguousArray(N, M, E, F);
    indexAddressGenerator(Ifmap, Filter, Psum, M, C, N, W, H, R, S, E, F, n, p, q, r, t);
    freeContiguousArray(Ifmap, N, C);
    freeContiguousArray(Filter, M, C);
    freeContiguousArray(Psum, N, M);
    return 0;
}

void indexAddressGenerator(int ****Ifmap, int ****Filter, int **** Psum, int M, int C, int N, int W, int H,
                            int R, int S, int E, int F, int n, int p, int q, int r, int t){
    // File pointers
    FILE *file1, *file2, *file3, *file4, *file5, *file6, *file7;

    // Open the first file in write mode
    file1 = fopen("ifmap_index.txt", "a+");
    if (file1 == NULL) {
        perror("Error opening ifmap_index.txt");
        return;
    }

    // Open the second file in write mode
    file2 = fopen("ifmap_address.txt", "a+");
    if (file2 == NULL) {
        perror("Error opening address.txt");
        fclose(file1); 
        return;
    }
    
    // Open the first file in write mode
    file3 = fopen("filter_index.txt", "a+");
    if (file3 == NULL) {
        perror("Error opening filter_index.txt");
        fclose(file1); 
        fclose(file2); 
        return;
    }

    // Open the second file in write mode
    file4 = fopen("filter_address.txt", "a+");
    if (file4 == NULL) {
        perror("Error opening filter_address.txt");
        fclose(file1); 
        fclose(file2); 
        fclose(file3); 
        return;
    }

    // Open the first file in write mode
    file5 = fopen("psum_index.txt", "a+");
    if (file5 == NULL) {
        perror("Error opening psum_index.txt");
        fclose(file1); 
        fclose(file2); 
        fclose(file3); 
        fclose(file4); 
        return;
    }

    // Open the second file in write mode
    file6 = fopen("psum_address.txt", "a+");
    if (file6 == NULL) {
        perror("Error opening psum_address.txt");
        fclose(file1); 
        fclose(file2); 
        fclose(file3); 
        fclose(file4); 
        fclose(file5); 
        return;
    }

    // Open the third file for reading
    file7 = fopen("scheduler.txt", "r");
    if (file7 == NULL) {
        printf("Error opening scheduler.txt");
        fclose(file1);
        fclose(file2); 
        fclose(file3);
        fclose(file4);
        fclose(file5);
        fclose(file6);  
        return;
    }
    
    clearFile("ifmap_index.txt");
    clearFile("ifmap_address.txt");
    clearFile("filter_index.txt");
    clearFile("filter_address.txt");
    clearFile("psum_index.txt");
    clearFile("psum_address.txt");

    char line[256];
    int pass_num, filter_start, filter_end, channel_start, channel_end, ifmap_start, ifmap_end;

    int cycle_count = 1;
    // Read and parse each line
    while (fgets(line, sizeof(line), file7) != NULL) {
        // Parse the line to extract values
        if (!strcmp(line, "processing passes are done\n")) {
            break;
        } 
        else if (sscanf(line, "processing pass %d: filter ids: %d-%d, channel ids: %d-%d, ifmap ids: %d-%d", 
                &pass_num, &filter_start, &filter_end, &channel_start, &channel_end, &ifmap_start, &ifmap_end) == 7) {
        } 

        ifmapAddressGenerator(file1, file2, Ifmap, W, H, n, q, r, ifmap_start, channel_start, pass_num);
        filterAddressGenerator(file3, file4, Filter, S, R, p, q, r, t, filter_start, channel_start, pass_num);
        psumAddressGenerator(file5, file6, Psum, F, E, n, p, t, ifmap_start, filter_start, pass_num);
        break;
    }
    
    fprintf(file1, "ifmap index generation is done");
    fprintf(file2, "ifmap address generation is done");
    fprintf(file3, "filter index generation is done");
    fprintf(file4, "filter address generation is done");
    fprintf(file5, "psum index generation is done");
    fprintf(file6, "psum address generation is done");

    fclose(file1);
    fclose(file2);
    fclose(file3);
    fclose(file4);
    fclose(file5);
    fclose(file6);
    fclose(file7);

    printf("Data written to all files successfully.\n");
}

void getParametersFromFile(const char* filename, int* M, int* C, int* N, int* W, int* H, int* R, int* S, 
                            int* E, int* F, int* n, int* p, int* q, int* r, int* t) {
    FILE* file = fopen(filename, "r");
    if (file == NULL) {
        perror("Error opening file");
        exit(EXIT_FAILURE);
    }

    char line[100];
    while (fgets(line, sizeof(line), file)) {
        char param[10];
        int value;
        
        // Read parameter name and value while ignoring comments
        if (sscanf(line, "%s = %d", param, &value) == 2) {
            if (strcmp(param, "M") == 0) *M = value;
            else if (strcmp(param, "C") == 0) *C = value;
            else if (strcmp(param, "N") == 0) *N = value;
            else if (strcmp(param, "W") == 0) *W = value;
            else if (strcmp(param, "H") == 0) *H = value;
            else if (strcmp(param, "R") == 0) *R = value;
            else if (strcmp(param, "S") == 0) *S = value;
            else if (strcmp(param, "E") == 0) *E = value;
            else if (strcmp(param, "F") == 0) *F = value;
            else if (strcmp(param, "n") == 0) *n = value;
            else if (strcmp(param, "p") == 0) *p = value;
            else if (strcmp(param, "q") == 0) *q = value;
            else if (strcmp(param, "r") == 0) *r = value;
            else if (strcmp(param, "t") == 0) *t = value;
        }
    }

    fclose(file);
}

void clearFile(const char* filename) {
    // Open the file in write mode to clear its contents
    FILE* file = fopen(filename, "w");

    // Check if the file opened successfully
    if (file == NULL) {
        perror("Failed to open file");
        return;
    }

    // Close the file immediately (since we just want to clear it)
    fclose(file);
}