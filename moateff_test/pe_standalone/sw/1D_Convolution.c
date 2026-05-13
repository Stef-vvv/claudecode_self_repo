#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "Convert_to_binary.c"

// Function prototypes
void getUserInput(int* num_filters, int* filter_width, int* num_ifmaps, int* ifmap_width, int* num_channels, int* stride);
void readFromFilesAndPerformConvolution(const char* filters_filename, int num_filters, int filter_width, 
                                        const char* ifmaps_filename, int num_ifmaps, int ifmap_width, 
                                        int num_channels, const char* baises_filename, int ofmap_width, int stride);
void readDataFromFile(const char* filename, int* data, int size);
void clearFile(const char* filename);
void interleaveData(const int* filters, int num_filters, int filter_width, int num_channels, int* interleaved_data);
void performConvolution(const int* filters, int num_filters, int filter_width, 
                        int** ifmaps, int num_ifmaps, int ifmap_width, int num_channels, int** baises,
                        int* ofmap, int ofmap_width, int stride) ;
void performConvolutionOneIfmap(const int* filters, int num_filters, int filter_width, 
                        const int* ifmap, int ifmap_width, int num_channels,
                        const int* biases, int* ofmap, int ofmap_width, int stride);
void writeDataToFile(const char* filename, const int* data, int size);
void displayFilterData(const int* filters, int num_filters, int filter_width, int num_channels);
void displayIfmapData(const int* ifmap, int ifmap_width, int num_channels);
void displayBiasesData(const int* baises,int ofmap_width,int num_filters);
void displayOfmapData(const int* ofmap, int num_filters, int ofmap_width);
void ConvertFilesToBinaryAndConcatenate(const char* filters_filename, const char* ifmaps_filename, const char* baises_filename, const char* ofmaps_filename);    void intToBinary16bit(int num, char* binaryStr);


void readFromFilesAndPerformConvolution(const char* filters_filename, int num_filters, int filter_width, 
                                        const char* ifmaps_filename, int num_ifmaps, int ifmap_width, 
                                        int num_channels, const char* baises_filename, int ofmap_width, int stride) {

    // Allocate memory for filters
    int* filters = (int*)malloc(num_filters * filter_width * num_channels * sizeof(int));
    
    // Read the filters data
    readDataFromFile(filters_filename, filters, num_filters * filter_width * num_channels);

    // Display the filter data
    displayFilterData(filters, num_filters, filter_width, num_channels);

    // Allocate memory for the interleaved data
    int* interleaved_filters = (int*)malloc(num_filters * filter_width * num_channels * sizeof(int));

    // Interleave the filters
    interleaveData(filters, num_filters, filter_width, num_channels, interleaved_filters);

    // Clear the contents of the file
    clearFile("interleaved_filters_data.txt");

    // Write the interleaved data to the file
    writeDataToFile("interleaved_filters_data.txt", interleaved_filters, num_filters * filter_width * num_channels);

    // Free the allocated memory
    free(interleaved_filters);

    // Allocate memory for input feature maps
    int** ifmaps = (int**)malloc(num_ifmaps * sizeof(int*));
    for (int i = 0; i < num_ifmaps; i++) {
        ifmaps[i] = (int*)malloc(ifmap_width * num_channels * sizeof(int));
    }

    // Read the input feature maps data
    for (int i = 0; i < num_ifmaps; i++) {
        readDataFromFile(ifmaps_filename, ifmaps[i], ifmap_width * num_channels);
    }
    
    // Display the input feature map data
    for (int i = 0; i < num_ifmaps; i++) {
        printf("Input Feature Map %d Data:\n", i + 1);
        displayIfmapData(ifmaps[i], ifmap_width, num_channels);
    }
    
    // Clear the contents of the file
    clearFile("interleaved_ifmaps_data.txt");

    // Write the interleaved data to the file
    for (int i = 0; i < num_ifmaps; i++) {
        writeDataToFile("interleaved_ifmaps_data.txt", ifmaps[i], ifmap_width * num_channels);
    }

    // Allocate memory for baises
    int** baises = (int**)malloc(num_ifmaps * sizeof(int*));
    for (int i = 0; i < num_ifmaps; i++) {
        baises[i] = (int*)malloc(ofmap_width * num_filters * sizeof(int));
    }

    // Read the input feature maps data
    for (int i = 0; i < num_ifmaps; i++) {
        readDataFromFile(baises_filename, baises[i], ofmap_width * num_filters);
    }
    
    // Display the input feature map data
    for (int i = 0; i < num_ifmaps; i++) {
        printf("Biases Data for Input Feature Map %d:\n", i + 1);
        displayBiasesData(baises[i], ofmap_width, num_filters);
    }
    
    // Allocate memory for interleaved baises
    int** interleaved_baises = (int**)malloc(num_ifmaps * sizeof(int*));
    for (int i = 0; i < num_ifmaps; i++) {
        interleaved_baises[i] = (int*)malloc(ofmap_width * num_filters * sizeof(int));
    }
    
    // Interleave the baises
    for (int i = 0; i < num_ifmaps; i++) {
        interleaveData(baises[i], num_filters, ofmap_width, 1, interleaved_baises[i]);
    }
    
    // Clear the contents of the file
    clearFile("interleaved_baises_data.txt");

    // Write the interleaved data to the file
    for (int i = 0; i < num_ifmaps; i++) {
        writeDataToFile("interleaved_baises_data.txt", interleaved_baises[i], num_filters * ofmap_width);
    }
    
    for (int i = 0; i < num_ifmaps; i++) {
        free(interleaved_baises[i]);
    }

    // Free the allocated memory
    free(interleaved_baises);
    
    // Allocate memory for output feature maps
    int* ofmap = (int*)malloc(num_filters * ofmap_width * sizeof(int));
    
    // Clear the contents of the files
    clearFile("ofmaps_data.txt");
    clearFile("interleaved_ofmaps_data.txt");

    // Perform convolution for each ifmap
    performConvolution(filters, num_filters, filter_width, ifmaps, num_ifmaps, ifmap_width, num_channels, baises, ofmap, ofmap_width, stride);

    ConvertFilesToBinaryAndConcatenate("interleaved_filters_data.txt", "interleaved_ifmaps_data.txt", 
                        "interleaved_baises_data.txt", "interleaved_ofmaps_data.txt");

    // Free allocated memory
    free(filters);
    for (int i = 0; i < num_ifmaps; i++) {
        free(ifmaps[i]);
    }
    free(ifmaps);
    free(ofmap);
}

// Function to get user input for convolution parameters
void getUserInput(int* num_filters, int* filter_width, int* num_ifmaps, int* ifmap_width, int* num_channels, int* stride) {
    printf("Enter the number of filters: ");
    scanf("%d", num_filters);
    printf("Enter the filter width: ");
    scanf("%d", filter_width);
    printf("Enter the number of ifmaps: ");
    scanf("%d", num_ifmaps);
    printf("Enter the ifmap width: ");
    scanf("%d", ifmap_width);
    printf("Enter the number of channels: ");
    scanf("%d", num_channels);
    printf("Enter the stride: ");
    scanf("%d", stride);
    printf("\n");
}

// Function to read data from a file into an array, ignoring comments
void readDataFromFile(const char* filename, int* data, int size) {
    static long lastPosition = 0;  // Static variable to remember the last position
    static char lastFile[256] = ""; // Store the last accessed file name

    FILE* file = fopen(filename, "r");
    if (file == NULL) {
        perror("Error opening file");
        exit(EXIT_FAILURE);
    }

    // If it's the same file as last time, seek to the saved position
    if (strcmp(lastFile, filename) == 0) {
        fseek(file, lastPosition, SEEK_SET);
    } else {
        lastPosition = 0;  // Reset position if a new file is opened
        strncpy(lastFile, filename, sizeof(lastFile) - 1);
        lastFile[sizeof(lastFile) - 1] = '\0'; // Ensure null termination
    }

    char line[256];
    int index = 0;

    while (fgets(line, sizeof(line), file) != NULL && index < size) {
        lastPosition = ftell(file);  // Save the current file position

        // Find the position of "//" in the line
        char* comment_start = strstr(line, "//");
        if (comment_start != NULL) {
            *comment_start = '\0'; // Terminate the line at the start of the comment
        }

        // Read integer values from the line
        char* token = strtok(line, " \t\n");
        while (token != NULL && index < size) {
            if (sscanf(token, "%d", &data[index]) == 1) {
                index++;
            }
            token = strtok(NULL, " \t\n");
        }
    }

    fclose(file);
}

#include <stdio.h>

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

// Function to interleave the filters row by row and column by column
void interleaveData(const int* filters, int num_filters, int filter_width, int num_channels, int* interleaved_data) {
    int index = 0;
    
    // Interleave filters row by row, column by column
    for (int i = 0; i < filter_width; i++) {  // Iterate over rows
        for (int c = 0; c < num_channels; c++) {  // Iterate over columns (channels)
            // For each row, column pair, interleave the data from each filter
            for (int f = 0; f < num_filters; f++) {
                int filter_idx = f * (filter_width * num_channels) + i * num_channels + c;
                interleaved_data[index++] = filters[filter_idx];  // Store the interleaved value
            }
        }
    }
}

// Function to perform convolution for each ifmap and accumulate results
void performConvolution(const int* filters, int num_filters, int filter_width, 
                        int** ifmaps, int num_ifmaps, int ifmap_width, int num_channels, int** baises,
                        int* ofmap, int ofmap_width, int stride) {
    
    int* interleaved_ofmaps = (int*)malloc(num_filters * ofmap_width * sizeof(int));

    for (int i = 0; i < num_ifmaps; i++) {
        // Initialize the output map for each ifmap
        memset(ofmap, 0, num_filters * ofmap_width * sizeof(int));
        
        // Perform convolution for each ifmap
        performConvolutionOneIfmap(filters, num_filters, filter_width, ifmaps[i], ifmap_width, num_channels, 
                                baises[i], ofmap, ofmap_width, stride);

        // Write output feature map to file
        writeDataToFile("ofmaps_data.txt", ofmap, ofmap_width * num_filters);

        // Display output on terminal
        printf("Output Feature Map %d:\n", i + 1);
        displayOfmapData(ofmap, num_filters, ofmap_width);
        
        // Interleave the ofmap
        interleaveData(ofmap, num_filters, ofmap_width, 1, interleaved_ofmaps);

        // Write the interleaved data to the file
        writeDataToFile("interleaved_ofmaps_data.txt", interleaved_ofmaps, num_filters * ofmap_width);
    }
    free(interleaved_ofmaps);
}

// Function to perform 1D convolution with 3-channel filters (per-pixel interleaving) and biases
void performConvolutionOneIfmap(const int* filters, int num_filters, int filter_width, 
                                const int* ifmap, int ifmap_width, int num_channels,
                                const int* biases, int* ofmap, int ofmap_width, int stride) {

    // Iterate over each filter
    for (int f = 0; f < num_filters; f++) {
        // Perform convolution for the current filter
        for (int i = 0; i < ofmap_width; i++) {
            ofmap[f * ofmap_width + i] = biases[f * ofmap_width + i]; // Initialize output value with bias
            
            // Dot product across filter width and channels
            for (int j = 0; j < filter_width; j++) {
                for (int c = 0; c < num_channels; c++) { // Loop over channels
                    int filter_idx = f * (filter_width * num_channels) + j * num_channels + c;
                    int ifmap_idx = (i * stride + j) * num_channels + c;

                    // Check bounds to avoid invalid memory access
                    if (filter_idx < num_filters * filter_width * num_channels &&
                        ifmap_idx < ifmap_width * num_channels) {
                        ofmap[f * ofmap_width + i] += filters[filter_idx] * ifmap[ifmap_idx];
                    }
                }
            }
        }
    }
}

// Function to write data to a file while keeping track of the last write position
void writeDataToFile(const char* filename, const int* data, int size) {
    static long lastPosition = 0;  // Track last write position
    static char lastFile[256] = ""; // Track last accessed file

   FILE* file = fopen(filename, "a+"); // Open in "read+write" mode to allow seeking

    if (file == NULL) {
        perror("Error opening output file");
        exit(EXIT_FAILURE);
    }

    // Check if it's the same file as before
    if (strcmp(lastFile, filename) == 0) {
        fseek(file, lastPosition, SEEK_SET);  // Resume from last saved position
    } else {
        lastPosition = ftell(file);  // Reset position if it's a new file
        strncpy(lastFile, filename, sizeof(lastFile) - 1);
        lastFile[sizeof(lastFile) - 1] = '\0'; // Ensure null termination
    }

    // Write the data to the file
    for (int i = 0; i < size; i++) {
        fprintf(file, "%d ", data[i]);
        fprintf(file, "\n");
    }

    lastPosition = ftell(file);  // Update position after writing

    fclose(file);
}

// Function to display filter data
void displayFilterData(const int* filters, int num_filters, int filter_width, int num_channels) {
    printf("Filter Data:\n");
    for (int f = 0; f < num_filters; f++) {
        printf("Filter %d: ", f + 1);
        for (int i = 0; i < filter_width * num_channels; i++) {
            printf("%d ", filters[f * filter_width * num_channels + i]);
        }
        printf("\n");
    }
    printf("\n");
}

// Function to display input feature map data
void displayIfmapData(const int* ifmap, int ifmap_width, int num_channels) {
    for (int i = 0; i < ifmap_width; i++) {
        for (int c = 0; c < num_channels; c++) {
            printf("%d ", ifmap[i * num_channels + c]);
        }
        printf("\n");
    }
    printf("\n");
}

// Function to display baises data
void displayBiasesData(const int* baises,int ofmap_width,int num_filters) {
    for (int f = 0; f < num_filters; f++) {
        printf("Filter %d: ", f + 1);
        for (int i = 0; i < ofmap_width; i++) {
            printf("%d ", baises[f * ofmap_width + i]);
        }
        printf("\n");
    }
    printf("\n");   
}


// Function to display output feature map data
void displayOfmapData(const int* ofmap, int num_filters, int ofmap_width) {
    for (int f = 0; f < num_filters; f++) {
        printf("Filter %d: ", f + 1);
        for (int i = 0; i < ofmap_width; i++) {
            printf("%d ", ofmap[f * ofmap_width + i]);
        }
        printf("\n");
    }
    printf("\n");
}
