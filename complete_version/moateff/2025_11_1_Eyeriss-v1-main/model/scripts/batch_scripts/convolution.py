#!/usr/bin/env python3
"""
Runs a 2D convolution over a batch of input feature maps (ifmaps)
after interactively prompting for all parameters and paths.
"""

import sys
import numpy as np
from pathlib import Path

# ------------------------- Fixed-point & I/O Helpers -------------------------

def bin16_to_int16(binstr: str) -> np.int16:
    """Convert 16-bit two's-complement binary string to int16."""
    val = int(binstr, 2)
    if val & 0x8000:
        val -= 1 << 16
    return np.int16(val)

def int16_to_bin16(x: np.int16) -> str:
    """Convert int16 to a 16-bit two's-complement binary string."""
    return format(np.uint16(x).item(), "016b")

def fixed_mul_q313(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """Element-wise multiply two Q3.13 int16 arrays."""
    prod32 = a.astype(np.int32) * b.astype(np.int32)
    shifted = prod32 >> 13
    return shifted.astype(np.int16)

def load_txt_int16(path: Path) -> np.ndarray:
    """Load a text file of 16-bit binary lines into a 1-D int16 NumPy array."""
    with path.open("r") as f:
        return np.array([bin16_to_int16(line.strip()) for line in f if line.strip()], dtype=np.int16)

def save_data(data: np.ndarray, output_path: Path):
    """Saves a NumPy array into the flat binary string format."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w") as f:
        for val in data.flatten():
            f.write(int16_to_bin16(val) + "\n")

# ------------------------- Generic 2D Convolution -------------------------

def conv2d_q313(ifmap, weights, biases, stride):
    """Performs a 2D convolution with Q3.13 fixed-point arithmetic."""
    H, W, C = ifmap.shape
    K, _, _, M = weights.shape
    OH = (H - K) // stride + 1
    OW = (W - K) // stride + 1
    ofmap = np.zeros((OH, OW, M), dtype=np.int16)

    for m in range(M):
        w_m = weights[:, :, :, m]
        b_m = biases[m]
        for oh in range(OH):
            for ow in range(OW):
                base_h, base_w = oh * stride, ow * stride
                window = ifmap[base_h:base_h+K, base_w:base_w+K, :]
                mult = fixed_mul_q313(window, w_m)
                acc32 = mult.astype(np.int32).sum() + int(b_m)
                ofmap[oh, ow, m] = np.int16(acc32)
    return ofmap

# ------------------------- Main Driver -------------------------

def main():
    """Interactively prompts for parameters and runs the batch convolution."""
    print("🚀 --- Interactive Batch 2D Convolution Simulator --- 🚀")
    
    try:
        # --- Get Paths and Parameters Interactively ---
        ifmap_dir_str = input("Enter the path to the INPUT FEATURE MAP directory: ").strip()
        output_dir_str = input("Enter the path to the OUTPUT directory: ").strip()
        weights_path_str = input("Enter the path to the WEIGHTS file: ").strip()
        bias_path_str = input("Enter the path to the BIAS file: ").strip()

        print("\nPlease provide the parameters for the convolution layer:")
        H = int(input("  Enter Input Feature Map Height (H): "))
        W = int(input("  Enter Input Feature Map Width (W): "))
        C = int(input("  Enter Input Feature Map Channels (C): "))
        M = int(input("  Enter Number of Filters (M): "))
        K = int(input("  Enter Kernel Size (K): "))
        S = int(input("  Enter Stride (S): "))

        # --- Setup Paths ---
        ifmap_dir = Path(ifmap_dir_str)
        output_dir = Path(output_dir_str)
        
        # --- Load weights and biases ONCE ---
        print("\n--- Loading weights and biases ---")
        weights_flat = load_txt_int16(Path(weights_path_str))
        biases = load_txt_int16(Path(bias_path_str))
        
        expected_weights_size = K**2 * C * M
        assert len(weights_flat) == expected_weights_size, "WEIGHTS size mismatch"
        assert len(biases) == M, "BIAS size mismatch"
        
        weights = weights_flat.reshape(M, C, K, K).transpose(2, 3, 1, 0)
        print("✅ Weights and biases loaded and reshaped successfully.")

        # --- Find all input files ---
        ifmap_files = list(ifmap_dir.glob('*.txt'))
        if not ifmap_files:
            print(f"❌ Error: No '.txt' files found in '{ifmap_dir}'.", file=sys.stderr)
            sys.exit(1)
            
        print(f"\n✅ Found {len(ifmap_files)} feature maps to process.")

        # --- Process each input feature map ---
        for ifmap_path in ifmap_files:
            print(f"\n--- Processing {ifmap_path.name} ---")
            ifmap_flat = load_txt_int16(ifmap_path)
            
            expected_ifmap_size = H * W * C
            assert len(ifmap_flat) == expected_ifmap_size, f"IFMAP size mismatch in {ifmap_path.name}"
            
            ifmap = ifmap_flat.reshape(C, H, W).transpose(1, 2, 0)
            
            conv_out = conv2d_q313(ifmap, weights, biases, stride=S)
            print(f"  - Convolution complete. New shape is {conv_out.shape}")
            
            output_path = output_dir / ifmap_path.name
            save_data(conv_out, output_path)
            print(f"  - Saved output to {output_path}")

    except (AssertionError, ValueError, FileNotFoundError) as e:
        print(f"\n❌ Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ An unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)
        
    print("\n✨ Batch processing complete.")

if __name__ == "__main__":
    main()