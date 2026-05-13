#include <stdio.h>

// Function prototypes
int ****allocateContiguousArray(int N, int C, int H, int W);
void freeContiguousArray(int ****Array, int N, int C);
int calculateAddress(int ****Array, int n, int c, int h, int w);

// Function to allocate a contiguous 4D array
int ****allocateContiguousArray(int N, int C, int H, int W) {
    // Allocate a single large block of memory
    int *data = (int *)malloc(N * C * H * W * sizeof(int));
    if (!data) {
        printf("Memory allocation failed!\n");
        exit(1);
    }

    // Allocate pointers for 4D indexing
    int ****Array = (int ****)malloc(N * sizeof(int ***));
    for (int i = 0; i < N; i++) {
        Array[i] = (int ***)malloc(C * sizeof(int **));
        for (int j = 0; j < C; j++) {
            Array[i][j] = (int **)malloc(H * sizeof(int *));
            for (int k = 0; k < H; k++) {
                // Point each Array[i][j][k] row to the correct location in the contiguous block
                Array[i][j][k] = data + (i * C * H * W) + (j * H * W) + (k * W);
            }
        }
    }
    return Array;
}

// Function to free the contiguous 4D array
void freeContiguousArray(int ****Array, int N, int C) {
    if (!Array) return; // Avoid freeing NULL pointer

    free(Array[0][0][0]); // Free the large contiguous block

    for (int i = 0; i < N; i++) {
        for (int j = 0; j < C; j++) {
            free(Array[i][j]); // Free H pointers
        }
        free(Array[i]); // Free C pointers
    }
    free(Array); // Free N pointers
}

// Function to compute address difference
int calculateAddress(int ****Array, int n, int c, int h, int w) {
    return &Array[n][c][h][w] - &Array[0][0][0][0]; // Returns difference in number of elements
}
