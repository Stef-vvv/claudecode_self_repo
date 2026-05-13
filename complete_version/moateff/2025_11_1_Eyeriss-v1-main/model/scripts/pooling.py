#!/usr/bin/env python3
"""
Performs max-pooling on a tensor of any shape.

The script interactively prompts the user for the input file, tensor dimensions,
pooling window size, and stride.
The output is saved as 'maxpool_output.txt' in the same directory as the input file.
"""
import sys
import numpy as np
from pathlib import Path

# ------------------------- Universal Helper Functions -------------------------

def bin16_to_int16(binstr: str) -> np.int16:
    """Converts a 16-bit two's-complement binary string to int16."""
    val = int(binstr, 2)
    if val & 0x8000:  # if sign bit is set, convert to negative
        val -= 1 << 16
    return np.int16(val)

def int16_to_bin16(x: np.int16) -> str:
    """Converts int16 to a 16-bit two's-complement binary string."""
    return format(np.uint16(x).item(), "016b")

def load_data(file_path: Path, shape: tuple) -> np.ndarray:
    """Loads a flat binary text file and reshapes it to the given dimensions."""
    with file_path.open("r") as f:
        data = np.array([bin16_to_int16(line.strip()) for line in f if line.strip()], dtype=np.int16)
    
    expected_elements = np.prod(shape)
    if data.size != expected_elements:
        raise ValueError(f"Shape mismatch: file has {data.size} elements, but shape {shape} requires {expected_elements}.")
        
    return data.reshape(shape)

def save_data(data: np.ndarray, output_path: Path):
    """Saves a NumPy array into the flat binary string format."""
    with output_path.open("w") as f:
        for val in data.flatten():
            f.write(int16_to_bin16(val) + "\n")

# ------------------------- Core Max-Pooling Operation -------------------------

def max_pooling_3d(input_3d: np.ndarray, pool_size: int, stride: int) -> np.ndarray:
    """
    Performs max-pooling on a 3D input tensor (H, W, C).
    
    Args:
        input_3d (np.ndarray): The input tensor of shape (H, W, C).
        pool_size (int): The size of the pooling window (e.g., 3 for a 3x3 window).
        stride (int): The step size to move the window across the tensor.
        
    Returns:
        np.ndarray: The tensor after max-pooling.
    """
    H, W, C = input_3d.shape

    # Calculate the dimensions of the output tensor
    out_H = (H - pool_size) // stride + 1
    out_W = (W - pool_size) // stride + 1
    
    # Initialize the output tensor with zeros
    pooled = np.zeros((out_H, out_W, C), dtype=input_3d.dtype)
    
    # Iterate over each channel
    for c in range(C):
        # Iterate over the output height
        for h in range(out_H):
            # Iterate over the output width
            for w in range(out_W):
                # Define the current window
                h_start = h * stride
                w_start = w * stride
                window = input_3d[h_start : h_start + pool_size, w_start : w_start + pool_size, c]
                
                # Find the maximum value in the window and assign it to the output
                pooled[h, w, c] = np.max(window)
                
    return pooled

# ------------------------- Main Driver -------------------------

def main():
    """Interactively prompts the user for parameters and performs max-pooling."""
    print("🚀 --- General-Purpose Max-Pooling Simulator --- 🚀")
    
    try:
        # --- Get Parameters Interactively ---
        print("\nPlease provide the input tensor dimensions:")
        H = int(input("  Enter Input Height (H): "))
        W = int(input("  Enter Input Width (W): "))
        C = int(input("  Enter Input Channels (C): "))
        
        print("\nPlease provide the max-pooling parameters:")
        pool_size = int(input("  Enter the Pool Size (e.g., 3 for a 3x3 window): "))
        stride = int(input("  Enter the Stride: "))
        
        # --- Get File Path ---
        input_path_str = input("\n  Enter the full path to the input file: ").strip()
        input_path = Path(input_path_str)
        
        # --- Automatically determine the output path ---
        output_path = input_path.parent / "maxpool_output.txt"
        
        # --- Processing Pipeline ---
        print("\nReading input file...")
        input_data = load_data(input_path, (H, W, C))
        print(f"✅ Loaded input data with shape {input_data.shape}")
        
        print("Performing max-pooling...")
        pooled_data = max_pooling_3d(input_data, pool_size, stride)
        print(f"✅ Max-pooling complete. New shape is {pooled_data.shape}")
        
        print(f"Writing output to {output_path}...")
        save_data(pooled_data, output_path)
        print("✅ Output saved successfully.")

    except ValueError as e:
        print(f"\n❌ Error: {e}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print(f"\n❌ Error: Input file not found at '{input_path_str}'", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ An unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
