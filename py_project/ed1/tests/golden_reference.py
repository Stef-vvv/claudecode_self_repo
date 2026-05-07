"""
Golden reference: Quantized integer conv2, matching Q8 data format.

Data format (ALL Q8 = 8-bit fractional):
  IFMAP:  Q8 (step = 1/256)
  FILTER: Q8 (step = 1/256)
  OUTPUT: Q8 (step = 1/256)

Computation: integer MAC, then right-shift 8 for output quantization.
Compare: float64 exact vs Q8 quantized vs reference file.
"""
import numpy as np
import time

def load_dat(filepath):
    with open(filepath) as f:
        return np.array([float(l.strip()) for l in f], dtype=np.float64)

def compute_q8_conv(ifmap_flat, filter_flat, H=16, W=16, C=32, F=64, K=3, pad=1):
    """
    Q8 quantized conv2: integer MAC then right-shift 8.
    Matches hardware fixed-point behavior.
    """
    H_pad, W_pad = H + 2*pad, W + 2*pad

    # Convert to Q8 integers
    ifmap_int = np.round(ifmap_flat * 256).astype(np.int32)
    filt_int = np.round(filter_flat * 256).astype(np.int32)

    # Reshape ifmap: C x H_pad x W_pad
    ifmap = np.zeros((C, H_pad, W_pad), dtype=np.int32)
    idx = 0
    for c in range(C):
        for h in range(H):
            ifmap[c, h+pad, 0+pad:W+pad] = ifmap_int[idx:idx+W]
            idx += W

    # Reshape filter: F x C x K x K
    filt = filt_int.reshape(F, C, K, K)

    # Compute OFM in integer domain
    ofmap_int = np.zeros((F, H, W), dtype=np.int32)
    for h in range(H):
        for w in range(W):
            patch = ifmap[:, h:h+K, w:w+K]  # C x K x K
            # Broadcast: (F,C,K,K) * (1,C,K,K) -> sum -> (F,)
            vals = np.sum(filt.astype(np.int64) * patch.astype(np.int64)[np.newaxis,:,:,:],
                          axis=(1,2,3))  # (F,) in Q16
            # Quantize to Q8: right shift 8, then ReLU
            vals_q8 = np.maximum(0, vals >> 8).astype(np.int32)
            ofmap_int[:, h, w] = vals_q8

    # Convert back to float
    ofmap_float = ofmap_int.flatten().astype(np.float64) / 256.0
    return ofmap_float

if __name__ == "__main__":
    ifmap = load_dat('conv2.input.real.dat')
    filt = load_dat('conv2.real.dat')
    ref = load_dat('conv2.output.real.dat')

    print(f"IFMAP: {len(ifmap)}, FILTER: {len(filt)}, REF: {len(ref)}")

    # Verify data is Q8
    ifmap_q8_ok = np.all(np.abs(ifmap * 256 - np.round(ifmap * 256)) < 1e-10)
    filt_q8_ok = np.all(np.abs(filt * 256 - np.round(filt * 256)) < 1e-10)
    ref_q8_ok = np.all(np.abs(ref * 256 - np.round(ref * 256)) < 1e-10)
    print(f"IFMAP Q8: {ifmap_q8_ok}, FILTER Q8: {filt_q8_ok}, REF Q8: {ref_q8_ok}")

    t0 = time.time()
    golden_q8 = compute_q8_conv(ifmap, filt)
    t1 = time.time()
    print(f"\nComputed Q8 golden in {t1-t0:.1f}s")

    # Compare Q8 golden vs reference
    abs_diff = np.abs(golden_q8 - ref)
    exact = np.sum(abs_diff < 1e-12)
    max_err = np.max(abs_diff)
    mean_err = np.mean(abs_diff)

    print(f"\nQ8 Golden vs Reference file:")
    print(f"  Exact matches: {exact}/{len(golden_q8)}")
    print(f"  Max error:     {max_err:.2e}")
    print(f"  Mean error:    {mean_err:.2e}")

    diff_idx = np.where(abs_diff >= 1e-12)[0]
    if len(diff_idx) > 0:
        print(f"  Differences: {len(diff_idx)}")
        print(f"  First 20:")
        for i in diff_idx[:20]:
            print(f"    [{i}] golden={golden_q8[i]:.10f} ref={ref[i]:.10f}")
    else:
        print(f"  *** PERFECT MATCH! Reference file is CORRECT. ***")

    np.savetxt('golden_q8_output.dat', golden_q8, fmt='%.10f')
    print(f"\nGolden saved to golden_q8_output.dat")
