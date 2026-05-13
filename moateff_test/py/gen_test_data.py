"""
Generate synthetic test data for Eyeriss v1 hardware verification.

Strategy: Use the existing Conv1 scan chain config (serial_data.txt already present),
but load a SMALL actual ifmap+filter (zero-padded to Conv1 dimensions) into GLB.
Only 1 of 64 filters has non-zero weights, so the output is predictable.

Data format:
- Q3.13 fixed-point: 16-bit signed, step=1/8192
- GLB: 4 banks × 16-bit, Port A writes 64-bit (4 values packed)
- Each line in data files: 64-bit binary string (4×16-bit concatenated)

GLB address layout (Row-Major):
- IFMAP: [batch][channel][row][col] = n*C*H*W + c*H*W + h*W + w
- FILTER: [filter][channel][row][col] = m*C*R*S + c*R*S + r*S + s
- BIAS: [filter] = m
"""

import numpy as np
import os

# ============================================================
# Q3.13 fixed-point helpers
# ============================================================
def float_to_q313(val):
    """Convert float to Q3.13 16-bit signed integer."""
    max_val = (2**15 - 1) / (2**13)
    min_val = -(2**15) / (2**13)
    val = max(min(val, max_val), min_val)
    return np.int16(round(val * (2**13)))

def q313_to_bin16(x):
    """Convert Q3.13 int16 to 16-bit binary string."""
    return format(np.uint16(x), '016b')

def pack_4x16_to_64bin(vals):
    """Pack 4 int16 values into one 64-bit binary string (little-endian within each 16)."""
    packed = ''
    for v in vals:
        packed = q313_to_bin16(v) + packed  # MSB first within 64-bit word
    return packed

# ============================================================
# Generate tiny test data padded to Conv1 dimensions
# ============================================================

# Actual test dimensions (tiny, for fast verification)
TEST_H, TEST_W = 5, 5       # ifmap spatial size
TEST_R, TEST_S = 3, 3       # filter spatial size
TEST_C = 3                   # input channels
TEST_M = 1                   # output filters (only use 1 for simplicity)

# Conv1 padded dimensions (must match scan chain config)
CFG_H, CFG_W = 227, 227
CFG_R, CFG_S = 11, 11
CFG_C = 3
CFG_M = 64
CFG_N = 4                    # batch size
CFG_U = 4                    # stride
CFG_D = 35                   # segment height (from shared_pkg)

# ============================================================
# Create test ifmap: small 5×5 pattern in top-left, rest zeros
# ============================================================
print("Generating test data...")

# Create full-sized ifmap array [N][C][H][W]
ifmap_full = np.zeros((CFG_N, CFG_C, CFG_H, CFG_W), dtype=np.int16)

# Fill a small pattern in the top-left of each channel for batch 0
test_patterns = [
    [[1, 2, 3, 4, 5],
     [6, 7, 8, 9, 10],
     [11,12,13,14,15],
     [16,17,18,19,20],
     [21,22,23,24,25]],
    [[2, 3, 4, 5, 6],
     [3, 4, 5, 6, 7],
     [4, 5, 6, 7, 8],
     [5, 6, 7, 8, 9],
     [6, 7, 8, 9, 10]],
    [[1, 1, 1, 1, 1],
     [2, 2, 2, 2, 2],
     [3, 3, 3, 3, 3],
     [4, 4, 4, 4, 4],
     [5, 5, 5, 5, 5]],
]

for c in range(TEST_C):
    for h in range(TEST_H):
        for w in range(TEST_W):
            ifmap_full[0, c, h, w] = float_to_q313(float(test_patterns[c][h][w]))

# ============================================================
# Create test filter: 3×3×3 non-zero, rest zero. Only filter[0] used.
# ============================================================
filter_full = np.zeros((CFG_M, CFG_C, CFG_R, CFG_S), dtype=np.int16)

# Filter 0: simple 3×3 edge detection-like pattern across 3 channels
filter_3x3x3 = [
    [[1, 0, -1], [2, 0, -2], [1, 0, -1]],   # channel 0
    [[1, 2, 1],   [0, 0, 0],  [-1,-2,-1]],    # channel 1
    [[0, 1, 0],   [1, -4, 1], [0, 1, 0]],     # channel 2
]

for c in range(TEST_C):
    for r in range(TEST_R):
        for s in range(TEST_S):
            filter_full[0, c, r, s] = float_to_q313(float(filter_3x3x3[c][r][s]))

# Filters 1..63 stay zero

# ============================================================
# Create bias: only bias[0] non-zero
# ============================================================
bias_full = np.zeros(CFG_M, dtype=np.int16)
bias_full[0] = float_to_q313(0.0)  # zero bias for simplicity

# ============================================================
# Compute expected output (golden reference) using Python
# ============================================================
print("Computing golden reference...")

# OFM dimensions for Conv1: E=55, F=55
CFG_E = 55
CFG_F = 55

# Compute convolution in Q3.13
ofmap_expected = np.zeros((CFG_N, CFG_M, CFG_F, CFG_E), dtype=np.int16)

for n in range(1):  # only batch 0
    for m in range(1):  # only filter 0
        for oh in range(CFG_F):
            for ow in range(CFG_E):
                h_start = oh * CFG_U
                w_start = ow * CFG_U
                acc = np.int32(0)
                for c in range(CFG_C):
                    for r in range(CFG_R):
                        for s in range(CFG_S):
                            if (h_start + r < CFG_H and w_start + s < CFG_W):
                                ifmap_val = np.int32(ifmap_full[n, c, h_start+r, w_start+s])
                                filter_val = np.int32(filter_full[m, c, r, s])
                                acc += (ifmap_val * filter_val) >> 13
                acc += np.int32(bias_full[m])
                # Clamp to int16
                if acc > 32767:
                    acc = 32767
                elif acc < -32768:
                    acc = -32768
                ofmap_expected[n, m, oh, ow] = np.int16(acc)

# Print expected output (non-zero values only for verification)
print("\nExpected output (non-zero values):")
nz_count = 0
for n in range(1):
    for m in range(1):
        for oh in range(CFG_F):
            for ow in range(CFG_E):
                v = ofmap_expected[n, m, oh, ow]
                if v != 0:
                    print(f"  ofmap[{n}][{m}][{oh}][{ow}] = {v}")
                    nz_count += 1
                    if nz_count >= 20:
                        break
                if nz_count >= 20:
                    break
            if nz_count >= 20:
                break
        if nz_count >= 20:
            break
    if nz_count >= 20:
        break

print(f"\nTotal non-zero output values: {np.count_nonzero(ofmap_expected)}")

# ============================================================
# Format data for testbench (64-bit words as binary strings)
# ============================================================
print("\nWriting data files...")

out_dir = "H:/moateff_test/test_data"
os.makedirs(out_dir, exist_ok=True)

# --- Bias data ---
# 64 bias values → 16 64-bit words (4 biases per word)
with open(f"{out_dir}/bias_64.txt", "w") as f:
    for i in range(0, CFG_M, 4):
        vals = [bias_full[i+j] if i+j < CFG_M else 0 for j in range(4)]
        f.write(pack_4x16_to_64bin(vals) + "\n")
print(f"  bias_64.txt: {CFG_M//4} words")

# --- Filter data ---
# CFG_M * CFG_C * CFG_R * CFG_S = 64 * 3 * 11 * 11 = 23232 values
# → 5808 64-bit words
with open(f"{out_dir}/filter_64.txt", "w") as f:
    count = 0
    for m in range(CFG_M):
        for c in range(CFG_C):
            for r in range(CFG_R):
                for s in range(CFG_S):
                    if count % 4 == 0:
                        vals = [0, 0, 0, 0]
                    vals[count % 4] = filter_full[m, c, r, s]
                    if count % 4 == 3:
                        f.write(pack_4x16_to_64bin(vals) + "\n")
                    count += 1
    # Write remaining partial word
    if count % 4 != 0:
        f.write(pack_4x16_to_64bin(vals) + "\n")
print(f"  filter_64.txt: {(count + 3) // 4} words")

# --- Ifmap data ---
# CFG_N * CFG_C * CFG_H * CFG_W = 4 * 3 * 227 * 227 = 618348 values
# → 154587 64-bit words
# But most are zeros. We write them all for correct address mapping.
# This is large but manageable.
IFMAP_WORDS = (CFG_N * CFG_C * CFG_H * CFG_W + 3) // 4
print(f"  ifmap_64.txt: {IFMAP_WORDS} words (this may be large)...")

with open(f"{out_dir}/ifmap_64.txt", "w") as f:
    count = 0
    vals = [0, 0, 0, 0]
    for n in range(CFG_N):
        for c in range(CFG_C):
            for h in range(CFG_H):
                for w in range(CFG_W):
                    vals[count % 4] = ifmap_full[n, c, h, w]
                    if count % 4 == 3:
                        f.write(pack_4x16_to_64bin(vals) + "\n")
                        vals = [0, 0, 0, 0]
                    count += 1
    if count % 4 != 0:
        f.write(pack_4x16_to_64bin(vals) + "\n")
print(f"  ifmap_64.txt: {(count + 3) // 4} words done")

# --- Expected output ---
# CFG_N * CFG_M * CFG_F * CFG_E = 4 * 64 * 55 * 55 = 774400 values
# → 193600 64-bit words
OPSUM_WORDS = (CFG_N * CFG_M * CFG_F * CFG_E + 3) // 4
with open(f"{out_dir}/expected_output_64.txt", "w") as f:
    count = 0
    vals = [0, 0, 0, 0]
    for n in range(CFG_N):
        for m in range(CFG_M):
            for h in range(CFG_F):
                for w in range(CFG_E):
                    vals[count % 4] = ofmap_expected[n, m, h, w]
                    if count % 4 == 3:
                        f.write(pack_4x16_to_64bin(vals) + "\n")
                        vals = [0, 0, 0, 0]
                    count += 1
    if count % 4 != 0:
        f.write(pack_4x16_to_64bin(vals) + "\n")
print(f"  expected_output_64.txt: {(count + 3) // 4} words done")

print("\n=== Data generation complete ===")
print(f"Files in {out_dir}/")
print(f"  test ifmap: {TEST_H}x{TEST_W}x{TEST_C} (zero-padded to {CFG_H}x{CFG_W}x{CFG_C})")
print(f"  test filter: {TEST_R}x{TEST_S}x{TEST_C} (zero-padded to {CFG_R}x{CFG_S}x{CFG_C}, only filter[0])")
print(f"  bias[0] = 0, all others zero")
print(f"  Only filter[0] non-zero → easy to verify output")
