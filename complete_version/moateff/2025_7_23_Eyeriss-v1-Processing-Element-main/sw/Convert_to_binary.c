#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINE_LENGTH 100 
#define PAD_STRING "0000000000000000"

void ConvertFilesToBinaryAndConcatenate(const char* filters_filename, const char* ifmaps_filename, const char* baises_filename, const char* ofmaps_filename);    void intToBinary16bit(int num, char* binaryStr);
void readAndWriteBinary(const char* inputFilename, const char* outputFilename);
void concatenateLines(const char* inputFilename, const char* outputFilename);

void ConvertFilesToBinaryAndConcatenate(const char* filters_filename, const char* ifmaps_filename, const char* baises_filename, const char* ofmaps_filename) {
    // Read integers from "input.txt" and write their binary representation to "output_binary.txt"
    readAndWriteBinary(filters_filename, "interleaved_filters_data_binary.txt");
    readAndWriteBinary(ifmaps_filename, "interleaved_ifmaps_data_binary.txt");
    readAndWriteBinary(baises_filename, "interleaved_baises_data_binary.txt");
    readAndWriteBinary(ofmaps_filename, "interleaved_ofmaps_data_binary.txt");
    
    // Example usage: Concatenate lines from "binary_data.txt" and write to "concatenated_output.txt"
    concatenateLines("interleaved_filters_data_binary.txt", "interleaved_filters_data_binary_concatenated.txt");
    concatenateLines("interleaved_baises_data_binary.txt", "interleaved_baises_data_binary_concatenated.txt");
    concatenateLines("interleaved_ofmaps_data_binary.txt", "interleaved_ofmaps_data_binary_concatenated.txt");
}

// Function to convert an integer to its 16-bit binary representation
void intToBinary16bit(int num, char* binaryStr) {
    for (int i = 15; i >= 0; i--) {
        binaryStr[15 - i] = (num & (1 << i)) ? '1' : '0'; // Set '1' or '0' in the string
    }
    binaryStr[16] = '\0'; // Null-terminate the string
}

// Function to read integers from a file, convert them to 16-bit binary, and write to another file
void readAndWriteBinary(const char* inputFilename, const char* outputFilename) {
    FILE* inputFile = fopen(inputFilename, "r");
    FILE* outputFile = fopen(outputFilename, "w");

    if (inputFile == NULL) {
        perror("Error opening input file");
        return;
    }
    if (outputFile == NULL) {
        perror("Error opening output file");
        fclose(inputFile);
        return;
    }

    int num;
    char binaryStr[17]; // To hold the 16-bit binary string

    while (fscanf(inputFile, "%d", &num) == 1) {
        intToBinary16bit(num, binaryStr); // Convert to binary
        fprintf(outputFile, "%s\n", binaryStr); // Write binary to output file
    }

    fclose(inputFile);
    fclose(outputFile);
}

// Function to concatenate every 4 lines in reverse order
void concatenateLines(const char* inputFile, const char* outputFile) {
    FILE* inputFilePtr = fopen(inputFile, "r");
    if (!inputFilePtr) {
        perror("Error opening input file");
        return;
    }

    FILE* outputFilePtr = fopen(outputFile, "w");
    if (!outputFilePtr) {
        perror("Error opening output file");
        fclose(inputFilePtr);
        return;
    }

    char lines[4][MAX_LINE_LENGTH]; // Store 4 lines at a time
    int lineCount = 0;

    while (fgets(lines[lineCount], sizeof(lines[lineCount]), inputFilePtr)) {
        // Remove newline character
        lines[lineCount][strcspn(lines[lineCount], "\n")] = 0;
        lineCount++;

        // Process every 4 lines
        if (lineCount == 4) {
            fprintf(outputFilePtr, "%s_%s_%s_%s\n", lines[3], lines[2], lines[1], lines[0]);
            lineCount = 0; // Reset counter
        }
    }

    // Handle remaining lines with zero-padding
    if (lineCount > 0) {
        for (int i = lineCount; i < 4; ++i) {
            strcpy(lines[i], PAD_STRING);
        }
        fprintf(outputFilePtr, "%s_%s_%s_%s\n", lines[3], lines[2], lines[1], lines[0]);
    }

    fclose(inputFilePtr);
    fclose(outputFilePtr);
}
