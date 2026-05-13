#include <stdio.h>
#include <stdlib.h>

#include "Random_data.c"
#include "1D_Convolution.c"

// Function prototypes
void getUserInput(int* num_filters, int* filter_width, int* num_ifmaps, int* ifmap_width, int* num_channels, int* stride);
void generateRandomFile(const char* filename, int numIntegers);
void readFromFilesAndPerformConvolution(const char* filters_filename, int num_filters, int filter_width, 
                                        const char* ifmaps_filename, int num_ifmaps, int ifmap_width, 
                                        int num_channels, const char* baises_filename, int ofmap_width, int stride);

// Main function to handle command-line arguments
int main(int argc, char* argv[]) {
    int num_filters, filter_width, num_ifmaps, ifmap_width, num_channels, stride;

    // Get user input for parameters
    getUserInput(&num_filters, &filter_width, &num_ifmaps, &ifmap_width, &num_channels,  &stride);

    // Calculate output feature map size
    int ofmap_width = (ifmap_width - filter_width + stride) / stride;

    const char* filters_file = "filters_data.txt";
    const char* ifmaps_file = "ifmaps_data.txt";
    const char* baises_file = "baises_data.txt";

    // If no files are passed, generate random ones
    if (argc < 4) {
        printf("No input files provided. Generating random files...\n");
        
        // Randomize the inputs
        generateRandomFile(filters_file, num_filters * filter_width * num_channels);
        generateRandomFile(ifmaps_file, num_ifmaps * ifmap_width * num_channels);
        generateRandomFile(baises_file, num_filters * num_ifmaps * ofmap_width);
        printf("\n");
    } else {
        filters_file = argv[1];
        ifmaps_file = argv[2];
        baises_file = argv[3];
    }
    
    readFromFilesAndPerformConvolution(filters_file, num_filters, filter_width, 
                        ifmaps_file, num_ifmaps, ifmap_width, num_channels, baises_file, ofmap_width, stride);

    return 0;
}