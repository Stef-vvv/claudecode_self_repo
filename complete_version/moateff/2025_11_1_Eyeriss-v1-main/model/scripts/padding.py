#!/usr/bin/env python3
"""
Applies zero-padding to a tensor of any shape.

The script interactively prompts the user for the input file, tensor dimensions,
and the amount of padding to apply to the height and width dimensions.
The output is saved as 'padding_output.txt' in the same directory as the input file.
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

# ------------------------- Core Padding Operation -------------------------

def apply_padding(data_array: np.ndarray, pad: int) -> np.ndarray:
    """
    Applies zero-padding to the height and width dimensions of a 3D feature map.
    
    Args:
        data_array (np.ndarray): The input tensor of shape (H, W, C).
        pad (int): The number of zeros to add to each side of the height and width.
        
    Returns:
        np.ndarray: The padded tensor.
    """
    if pad == 0:
        return data_array
    # The padding format is ((top, bottom), (left, right), (before_c, after_c))
    return np.pad(data_array, ((pad, pad), (pad, pad), (0, 0)), 'constant', constant_values=0)

# ------------------------- Main Driver -------------------------

def main():
    """Interactively prompts the user for parameters and applies padding."""
    print("🚀 --- General-Purpose Padding Applicator --- �")
    
    try:
        # --- Get Parameters Interactively ---
        print("\nPlease provide the input tensor dimensions:")
        H = int(input("  Enter Input Height (H): "))
        W = int(input("  Enter Input Width (W): "))
        C = int(input("  Enter Input Channels (C): "))
        
        padding_amount = int(input("\n  Enter the amount of padding to apply: "))
        
        # --- Get File Path ---
        input_path_str = input("\n  Enter the full path to the input file: ").strip()
        input_path = Path(input_path_str)
        
        # --- Automatically determine the output path ---
        output_path = input_path.parent / "padding_output.txt"
        
        # --- Processing Pipeline ---
        print("\nReading input file...")
        input_data = load_data(input_path, (H, W, C))
        print(f"✅ Loaded input data with shape {input_data.shape}")
        
        print("Applying padding...")
        padded_data = apply_padding(input_data, padding_amount)
        print(f"✅ Applied padding. New shape is {padded_data.shape}")
        
        print(f"Writing output to {output_path}...")
        save_data(padded_data, output_path)
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
