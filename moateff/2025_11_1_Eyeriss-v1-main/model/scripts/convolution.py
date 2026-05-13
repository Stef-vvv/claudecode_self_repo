#!/usr/bin/env python3
"""
Run a generic 2D convolution layer (e.g., for a CNN) in Q3.13 fixed-point
arithmetic. The script interactively prompts the user for all layer
parameters and individual file paths.

The output is automatically saved as 'conv_output.txt' in the same
directory as the input feature map.
"""

import sys
import numpy as np
from pathlib import Path

# --------------------------------------------------------------------
# Fixed-point helpers (Q3.13 stored in int16)
# --------------------------------------------------------------------
def bin16_to_int16(binstr: str) -> np.int16:
    """Convert a 16-bit two's-complement binary string to int16."""
    val = int(binstr, 2)
    if val & 0x8000:  # if sign bit set, convert to negative
        val -= 1 << 16
    return np.int16(val)

def int16_to_bin16(x: np.int16) -> str:
    """Convert int16 to a 16-bit two's-complement binary string."""
    return format(np.uint16(x).item(), "016b")

def fixed_mul_q313(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """
    Element-wise multiply two Q3.13 int16 arrays.
    The 32-bit product is shifted right by 13 to return to Q3.13 format.
    """
    prod32 = a.astype(np.int32) * b.astype(np.int32)  # Q6.26
    shifted = prod32 >> 13                            # Back to Q3.13
    low16 = shifted & 0xFFFF                          # Keep low 16 bits
    return low16.astype(np.int16)                     # Safe cast

# --------------------------------------------------------------------
# Generic 2D convolution
# --------------------------------------------------------------------
def conv2d_q313(ifmap, weights, biases, stride):
    """
    Performs a 2D convolution with Q3.13 fixed-point arithmetic.
    Assumes zero padding.

    ifmap   : (H, W, C)      Input feature map (Q3.13 int16)
    weights : (K, K, C, M)   Filter weights (Q3.13 int16)
    biases  : (M,)           Filter biases (Q3.13 int16)
    stride  : int            The stride of the convolution
    returns : (OH, OW, M)    Output feature map (Q3.13 int16, wrap-around)
    """
    H, W, C = ifmap.shape
    K, _, _, M = weights.shape
    OH = (H - K) // stride + 1
    OW = (W - K) // stride + 1

    ofmap = np.zeros((OH, OW, M), dtype=np.int16)

    for m in range(M):
        w_m = weights[:, :, :, m]
        b_m = biases[m]
        for oh in range(OH):
            base_h = oh * stride
            for ow in range(OW):
                base_w = ow * stride
                window = ifmap[base_h:base_h+K, base_w:base_w+K, :]
                mult = fixed_mul_q313(window, w_m)
                acc32 = mult.astype(np.int32).sum() + int(b_m)
                ofmap[oh, ow, m] = np.int16(acc32)  # wrap-around
    return ofmap

# --------------------------------------------------------------------
# I/O helpers
# --------------------------------------------------------------------
def load_txt_int16(path: Path) -> np.ndarray:
    """Load a text file of 16-bit binary lines into a 1-D int16 NumPy array."""
    with path.open("r") as f:
        return np.array([bin16_to_int16(line.strip()) for line in f if line.strip()], dtype=np.int16)

# --------------------------------------------------------------------
# Main driver
# --------------------------------------------------------------------
def main():
    """Interactively prompts the user for parameters and runs the convolution."""
    print("🚀 --- Generic 2D Convolution Layer Simulator --- 🚀")
    
    # --- Get Numeric Parameters Interactively ---
    try:
        print("\nPlease provide the parameters for the convolution layer:")
        H = int(input("  Enter Input Feature Map Height (H): "))
        W = int(input("  Enter Input Feature Map Width (W): "))
        C = int(input("  Enter Input Feature Map Channels (C): "))
        M = int(input("  Enter Number of Filters (M): "))
        K = int(input("  Enter Kernel Size (K): "))
        S = int(input("  Enter Stride (S): "))
    except ValueError:
        print("\n❌ Error: All parameters must be valid integers.", file=sys.stderr)
        sys.exit(1)

    # --- Get Individual File Paths ---
    print("\nPlease provide the full path for each input file:")
    ifmap_path = Path(input("  Enter path to the IFMAP file: ").strip())
    weights_path = Path(input("  Enter path to the WEIGHTS file: ").strip())
    bias_path = Path(input("  Enter path to the BIAS file: ").strip())

    # --- Automatically determine the output path ---
    output_path = ifmap_path.parent / "conv_output.txt"
    
    try:
        # ---------- read ----------
        print("\nReading input files...")
        ifmap_flat = load_txt_int16(ifmap_path)
        weights_flat = load_txt_int16(weights_path)
        biases = load_txt_int16(bias_path)

        # ---------- validate dimensions ----------
        print("Validating file sizes against parameters...")
        expected_ifmap_size = H * W * C
        expected_weights_size = K * K * C * M
        expected_biases_size = M
        assert len(ifmap_flat) == expected_ifmap_size, \
            f"IFMAP size mismatch: file has {len(ifmap_flat)} elements, expected {expected_ifmap_size}"
        assert len(weights_flat) == expected_weights_size, \
            f"WEIGHTS size mismatch: file has {len(weights_flat)} elements, expected {expected_weights_size}"
        assert len(biases) == expected_biases_size, \
            f"BIASES size mismatch: file has {len(biases)} elements, expected {expected_biases_size}"

        # ---------- reshape ----------
        print("Reshaping arrays for computation...")
        ifmap = ifmap_flat.reshape(C, H, W).transpose(1, 2, 0)
        weights = weights_flat.reshape(M, C, K, K).transpose(2, 3, 1, 0)

        # ---------- compute ----------
        print("Performing convolution...")
        conv_out = conv2d_q313(ifmap, weights, biases, stride=S)

        # ---------- write ----------
        print(f"Writing output to: {output_path}")
        OH, OW, _ = conv_out.shape
        with output_path.open("w") as f:
            for m in range(M):
                fmap = conv_out[:, :, m].ravel()
                for val in fmap:
                    f.write(int16_to_bin16(val) + "\n")

        print(f"\n✅ Done. Output dimensions: ({OH}, {OW}, {M}). Total lines written: {OH * OW * M}")

    except FileNotFoundError as e:
        print(f"\n❌ Error: Required file not found: {e.filename}", file=sys.stderr)
        sys.exit(1)
    except AssertionError as e:
        print(f"\n❌ Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ An unexpected error occurred: {e}", file=sys.stderr)
        sys.exit(1)

# --------------------------------------------------------------------
if __name__ == "__main__":
    main()