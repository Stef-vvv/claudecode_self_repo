#!/usr/bin/env python3
"""
Applies zero-padding to a batch of tensors after interactively
prompting the user for all necessary parameters.
"""
import sys
import numpy as np
from pathlib import Path

# ------------------------- Universal Helper Functions -------------------------

def bin16_to_int16(binstr: str) -> np.int16:
    """Converts a 16-bit two's-complement binary string to int16."""
    val = int(binstr, 2)
    if val & 0x8000:
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
        raise ValueError(f"Shape mismatch in {file_path.name}: file has {data.size} elements, but shape {shape} requires {expected_elements}.")
        
    return data.reshape(shape)

def save_data(data: np.ndarray, output_path: Path):
    """Saves a NumPy array into the flat binary string format."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w") as f:
        for val in data.flatten():
            f.write(int16_to_bin16(val) + "\n")

# ------------------------- Core Padding Operation -------------------------

def apply_padding(data_array: np.ndarray, pad: int) -> np.ndarray:
    """Applies zero-padding to the height and width dimensions of a 3D feature map."""
    if pad == 0:
        return data_array
    return np.pad(data_array, ((pad, pad), (pad, pad), (0, 0)), 'constant', constant_values=0)

# ------------------------- Main Driver -------------------------

def main():
    """Interactively prompts for parameters and runs the batch padding process."""
    print("🚀 --- Interactive Batch Padding Applicator --- 🚀")
    
    try:
        # --- Get Paths and Parameters Interactively ---
        input_dir_str = input("Enter the path to the INPUT directory: ").strip()
        output_dir_str = input("Enter the path to the OUTPUT directory: ").strip()
        
        print("\nPlease provide the input tensor dimensions:")
        H = int(input("  Enter Input Height (H): "))
        W = int(input("  Enter Input Width (W): "))
        C = int(input("  Enter Input Channels (C): "))
        
        padding_amount = int(input("\n  Enter the amount of padding to apply: "))

        # --- Setup Paths and Find Files ---
        input_dir = Path(input_dir_str)
        output_dir = Path(output_dir_str)
        shape = (H, W, C)

        input_files = list(input_dir.glob('*.txt'))
        if not input_files:
            print(f"❌ Error: No '.txt' files found in '{input_dir}'.", file=sys.stderr)
            sys.exit(1)

        print(f"\n✅ Found {len(input_files)} files to process in '{input_dir}'.")

        # --- Process Each File ---
        for input_path in input_files:
            print(f"\n--- Processing {input_path.name} ---")
            
            input_data = load_data(input_path, shape)
            print(f"  - Loaded data with shape {input_data.shape}")
            
            padded_data = apply_padding(input_data, padding_amount)
            print(f"  - Applied padding. New shape is {padded_data.shape}")
            
            output_path = output_dir / input_path.name
            save_data(padded_data, output_path)
            print(f"  - Saved output to {output_path}")

    except (ValueError, FileNotFoundError) as e:
        print(f"\n❌ Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ An unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)

    print("\n✨ Batch processing complete.")

if __name__ == "__main__":
    main()