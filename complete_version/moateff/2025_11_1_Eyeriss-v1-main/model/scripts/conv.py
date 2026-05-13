#!/usr/bin/env python3
import sys
import numpy as np
from pathlib import Path

# ------------------------- Fixed‑Point Helpers -------------------------
def bin16_to_int16(binstr: str) -> np.int16:
    val = int(binstr, 2)
    if val & 0x8000:
        val -= 1 << 16
    return np.int16(val)

def int16_to_bin16(x: np.int16) -> str:
    return format(np.uint16(x).item(), "016b")

def fixed_mul_q313(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    prod32 = a.astype(np.int32) * b.astype(np.int32)
    shifted = prod32 >> 13
    low16 = shifted & 0xFFFF
    return low16.astype(np.int16)

# ------------------------- Convolution Core -------------------------
def conv2d_q313(ifmap, weights, biases, kernel_size, stride):
    H, W, C = ifmap.shape
    K = kernel_size
    _, _, _, M = weights.shape
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
                ofmap[oh, ow, m] = np.int16(acc32)
    return ofmap

# ------------------------- I/O -------------------------
def load_txt_int16(path: Path) -> np.ndarray:
    with path.open("r") as f:
        return np.array([bin16_to_int16(line.strip()) for line in f], dtype=np.int16)

def main():
    print("=== Q3.13 Convolution Runner ===")
    ifmap_path = Path(input("Enter path to IFMAP .txt file: ").strip())
    weights_path = Path(input("Enter path to WEIGHTS .txt file: ").strip())
    biases_path = Path(input("Enter path to BIASES .txt file: ").strip())
    output_path = Path(input("Enter path for OUTPUT .txt file: ").strip())

    # Layer params
    H = int(input("Input height: "))
    W = int(input("Input width: "))
    C = int(input("Input channels: "))
    K = int(input("Kernel size (e.g., 11): "))
    S = int(input("Stride: "))
    M = int(input("Number of filters: "))

    # Read and reshape IFMAP
    ifmap_flat = load_txt_int16(ifmap_path)
    ifmap = ifmap_flat.reshape(C, H, W).transpose(1, 2, 0)  # (H, W, C)

    # Read and reshape WEIGHTS
    weights_flat = load_txt_int16(weights_path)
    weights = weights_flat.reshape(M, C, K, K).transpose(2, 3, 1, 0)  # (K, K, C, M)

    # Read BIASES
    biases = load_txt_int16(biases_path)
    assert biases.shape == (M,), f"Expected {M} biases, got {biases.shape}"

    # Run convolution
    ofmap = conv2d_q313(ifmap, weights, biases, kernel_size=K, stride=S)
    OH, OW, _ = ofmap.shape

    # Write output
    with output_path.open("w") as f:
        for m in range(M):
            fmap = ofmap[:, :, m].ravel()
            for val in fmap:
                f.write(int16_to_bin16(val) + "\n")

    print(f"✅ Done. Output shape: ({OH}, {OW}, {M}) → {OH*OW*M} lines")
    print(f"📁 Saved to: {output_path}")

# -------------------------
if __name__ == "__main__":
    main()