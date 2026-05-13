#include <stdio.h>
#include <stdlib.h>
#include <time.h>

void generateRandomFile(const char* filename, int numIntegers);
void generateRandomDataToFile(const char* filename, int numIntegers, int minValue, int maxValue);

void generateRandomFile(const char* filename, int numIntegers) {
    // Generate and write 100 random integers between 1 and 1000 to "random_data.txt"
    generateRandomDataToFile(filename, numIntegers, 1, 10);
}

// Function to generate random integers and write them to a file
void generateRandomDataToFile(const char* filename, int numIntegers, int minValue, int maxValue) {
    FILE* file = fopen(filename, "w+"); // Open the file in write mode

    if (file == NULL) {
        perror("Error opening file");
        return;
    }

    // Seed the random number generator
    srand(time(NULL));

    for (int i = 0; i < numIntegers; i++) {
        // Generate a random integer in the given range
        int randomValue = rand() % (maxValue - minValue + 1) + minValue;
        fprintf(file, "%d\n", randomValue); // Write the random number to the file
    }

    fclose(file);
    printf("Random data has been written to '%s'.\n", filename);
}
