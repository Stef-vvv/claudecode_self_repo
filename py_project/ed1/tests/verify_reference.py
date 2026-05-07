"""
Pure Python reference conv2 to verify the reference output file.
Layer-3: Conv, IFM=16x16x32, OFM=16x16x64, K=3x3, stride=1, pad=1, ReLU
Q_IN=5, Q_OUT=5, Q_W=8
"""
import os, sys
sys.path.insert(0, 'H:/cc_project/py_project')

def load_flat_data(filepath):
    with open(filepath) as f:
        return [float(line.strip()) for line in f]

def compute_conv2_reference(ifmap_flat, filter_flat, H=16, W=16, C=32, F=64, K=3, stride=1, pad=1):
    """
    Pure Python conv2: OFM[f][h][w] = sum_c(sum_kh(sum_kw(IFM[c][h+kh][w+kw] * FILT[f][c][kh][kw])))
    Applies ReLU on final output.
    """
    # Reshape ifmap: C x (H+2*pad) x (W+2*pad) with zero padding
    H_pad = H + 2*pad
    W_pad = W + 2*pad
    ifmap = [[[0.0]*W_pad for _ in range(H_pad)] for _ in range(C)]
    idx = 0
    for c in range(C):
        for h in range(H):
            for w in range(W):
                ifmap[c][h+pad][w+pad] = ifmap_flat[idx]
                idx += 1

    # Reshape filter: F x C x K x K
    filt = [[[[0.0]*K for _ in range(K)] for _ in range(C)] for _ in range(F)]
    idx = 0
    for f in range(F):
        for c in range(C):
            for kh in range(K):
                for kw in range(K):
                    filt[f][c][kh][kw] = filter_flat[idx]
                    idx += 1

    # Compute OFM
    out_H = (H_pad - K) // stride + 1  # should be 16
    out_W = (W_pad - K) // stride + 1  # should be 16
    ofmap = [[[0.0]*out_W for _ in range(out_H)] for _ in range(F)]

    for f in range(F):
        for h in range(out_H):
            for w in range(out_W):
                acc = 0.0
                for c in range(C):
                    for kh in range(K):
                        for kw in range(K):
                            ifm_val = ifmap[c][h*stride+kh][w*stride+kw]
                            fil_val = filt[f][c][kh][kw]
                            acc += ifm_val * fil_val
                # ReLU
                ofmap[f][h][w] = max(0.0, acc)

    # Flatten: F x H x W
    flat = []
    for f in range(F):
        for h in range(out_H):
            for w in range(out_W):
                flat.append(ofmap[f][h][w])
    return flat

if __name__ == "__main__":
    # Load data
    ifmap_flat = load_flat_data('conv2.input.real.dat')
    filter_flat = load_flat_data('conv2.real.dat')
    ref_flat = load_flat_data('conv2.output.real.dat')

    print(f"IFMAP: {len(ifmap_flat)} values (expected 16*16*32=8192)")
    print(f"FILTER: {len(filter_flat)} values (expected 64*32*3*3=18432)")
    print(f"REF OUTPUT: {len(ref_flat)} values (expected 64*16*16=16384)")

    # Compute reference
    my_out = compute_conv2_reference(ifmap_flat, filter_flat)
    print(f"MY OUTPUT: {len(my_out)} values")

    # Compare
    if len(my_out) == len(ref_flat):
        exact = sum(1 for i in range(len(ref_flat)) if abs(my_out[i] - ref_flat[i]) < 1e-12)
        within_eps = sum(1 for i in range(len(ref_flat)) if abs(my_out[i] - ref_flat[i]) < 0.001)
        diffs = [(i, ref_flat[i], my_out[i]) for i in range(len(ref_flat)) if abs(my_out[i] - ref_flat[i]) >= 1e-12]

        print(f"\nExact matches: {exact}/{len(ref_flat)}")
        print(f"Within 0.001: {within_eps}/{len(ref_flat)}")
        print(f"Any diff at all: {len(diffs)}")

        if diffs:
            print(f"First 10 diffs:")
            for i, r, m in diffs[:10]:
                print(f"  [{i}] ref={r:.10f} my={m:.10f} delta={abs(r-m):.2e}")
    else:
        print(f"Length mismatch!")
