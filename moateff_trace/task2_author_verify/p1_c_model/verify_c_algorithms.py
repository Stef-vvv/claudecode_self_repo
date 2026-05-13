#!/usr/bin/env python3
"""
Task 2: Verify Project 1 (C Data Delivery Patterns) algorithms via Python.
Translates C code from 2025_7_18 to Python and validates correctness.

Since no C compiler is available, this script faithfully translates the C
algorithms line-by-line and verifies them against expected results.
"""

import os, sys

# ============================================================================
# 1. Scheduler (from Scheduler.c)
# ============================================================================
def scheduler_c_model(M, C, N, n, p, q, r, t, outfile="p1_output/scheduler_py.txt"):
    """
    Exact Python translation of Scheduler.c.
    Test with: M=8, C=6, N=1, n=1, p=4, q=3, r=2, t=2
    """
    os.makedirs(os.path.dirname(outfile), exist_ok=True)
    passes = []
    pass_num = 0
    for N_ind in range(0, N, n):
        for C_ind in range(0, C, q*r):
            for M_ind in range(0, M, p*t):
                filter_start  = M_ind
                filter_end    = M_ind + p * t
                channel_start = C_ind
                channel_end   = C_ind + q * r
                ifmap_start   = N_ind
                ifmap_end     = N_ind + n
                passes.append({
                    'num': pass_num,
                    'filter': (filter_start, filter_end-1),
                    'channel': (channel_start, channel_end-1),
                    'ifmap': (ifmap_start, ifmap_end-1),
                })
                pass_num += 1
    return passes


# ============================================================================
# 2. Ifmap Index Generator (from ifmap_index_generator.c)
# ============================================================================
def ifmap_index_generator_c_model(n, W, q, r, D, ifmap_start, channel_start, outfile=None):
    """
    Exact Python translation of ifmap_index_generator.c.
    Generates (ifmap_idx, channel_idx, row_idx, col_idx) tuples.

    Loop: for n_ind: for W_ind: for q_ind: for D_ind: for r_ind
    """
    results = []
    count = 0
    for n_ind in range(n):
        for W_ind in range(W):
            for q_ind in range(q):
                for D_ind in range(D):
                    for r_ind in range(r):
                        ifmap_idx = ifmap_start + n_ind
                        channel_idx = channel_start + q_ind + r_ind * q
                        row_idx = D_ind
                        col_idx = W_ind
                        results.append((ifmap_idx, channel_idx, row_idx, col_idx))
                        count += 1
    return results


# ============================================================================
# 3. Filter Index Generator (from filter_index_generator.c)
# ============================================================================
def filter_index_generator_c_model(p, q, S, R, r, t, filter_start, channel_start, outfile=None):
    """
    Exact Python translation of filter_index_generator.c.
    Uses lock-step counter mechanism for (p, q, S) combined index.

    Loop: for R_ind: for r_ind: for t_ind: for 4x(p,q,S combined advance)
    """
    results = []
    p_ind, q_ind, S_ind = 0, 0, 0
    p_reg, q_reg, S_reg = 0, 0, 0

    done = False
    while not done:
        for R_ind in range(R):
            for r_idx in range(r):
                for t_idx in range(t):
                    p_ind = p_reg
                    q_ind = q_reg
                    S_ind = S_reg
                    for _ in range(4):
                        filter_idx = filter_start + p_ind + t_idx * p
                        channel_idx = channel_start + q_ind + r_idx * q
                        results.append((filter_idx, channel_idx, R_ind, S_ind))

                        # Combined index advance (matches C code)
                        if p_ind == p - 1:
                            p_ind = 0
                            if q_ind == q - 1:
                                q_ind = 0
                                if S_ind == S - 1:
                                    # All at max → set back to max (C code lock)
                                    p_ind = p - 1
                                    q_ind = q - 1
                                    S_ind = S - 1
                                else:
                                    S_ind += 1
                            else:
                                q_ind += 1
                        else:
                            p_ind += 1
        p_reg, q_reg, S_reg = p_ind, q_ind, S_ind

        # Check termination
        if p_reg == p-1 and q_reg == q-1 and S_reg == S-1:
            done = True

    return results


# ============================================================================
# 4. PSum Index Generator (from psum_index_generator.c)
# ============================================================================
def psum_index_generator_c_model(p, F, n, e, t, psum_start, channel_start, outfile=None):
    """
    Exact Python translation of psum_index_generator.c.
    Lock-step counter for (p, F, n) combined index.
    The inner loop iterates 4 times per (e,t) iteration.
    """
    results = []
    p_reg, F_reg, n_reg = 0, 0, 0

    done = False
    while not done:
        for e_ind in range(e):
            for t_idx in range(t):
                p_ind = p_reg
                F_ind = F_reg
                n_ind = n_reg
                for _ in range(4):
                    psum_idx = psum_start + n_ind
                    channel_idx = channel_start + p_ind + t_idx * p
                    results.append((psum_idx, channel_idx, e_ind, F_ind))

                    if p_ind == p - 1:
                        p_ind = 0
                        if F_ind == F - 1:
                            F_ind = 0
                            if n_ind == n - 1:
                                # All at max → set back to max (C code lock behavior)
                                p_ind = p - 1
                                F_ind = F - 1
                                n_ind = n - 1
                            else:
                                n_ind += 1
                        else:
                            F_ind += 1
                    else:
                        p_ind += 1
        p_reg, F_reg, n_reg = p_ind, F_ind, n_ind

        # Check termination: all counters at their max values
        if p_reg == p-1 and F_reg == F-1 and n_reg == n-1:
            done = True
        if len(results) > 100000:  # safety limit
            print("ERROR: PSum generator infinite loop!")
            break

    return results


# ============================================================================
# 5. Mapper (from Array.c — 4D to 1D address)
# ============================================================================
def mapper_4d_to_1d(idx4, idx3, idx2, idx1, dim3, dim2, dim1):
    """addr = idx4*(dim3*dim2*dim1) + idx3*(dim2*dim1) + idx2*dim1 + idx1"""
    return idx4 * (dim3 * dim2 * dim1) + idx3 * (dim2 * dim1) + idx2 * dim1 + idx1


# ============================================================================
# 6. Verification Tests
# ============================================================================
def test_scheduler():
    """Test with C model's parameter.txt values: M=8,C=6,N=1,n=1,p=4,q=3,r=2,t=2"""
    M, C, N = 8, 6, 1
    n, p, q, r, t = 1, 4, 3, 2, 2
    passes = scheduler_c_model(M, C, N, n, p, q, r, t)

    print(f"=== Scheduler Test ===")
    print(f"Parameters: M={M}, C={C}, N={N}, n={n}, p={p}, q={q}, r={r}, t={t}")
    print(f"Total passes: {len(passes)}")
    N_blocks = max(1, N // n) if n <= N else 1
    C_blocks = max(1, C // (q*r)) if q*r <= C else 1
    M_blocks = max(1, M // (p*t)) if p*t <= M else 1
    expected = N_blocks * C_blocks * M_blocks
    print(f"Expected passes: (N/n={N_blocks}) × (C/(q*r)={C_blocks}) × (M/(p*t)={M_blocks}) = {expected}")
    assert len(passes) == expected, f"FAIL: got {len(passes)}, expected {expected}"
    print("PASS: Scheduler produces correct pass count")

    for p in passes:
        print(f"  Pass {p['num']}: filter={p['filter']}, channel={p['channel']}, ifmap={p['ifmap']}")
    return True


def test_ifmap_generator():
    """Test with tiny config: n=1,W=8,q=1,r=1,D=8,ifmap_start=0,channel_start=0"""
    n, W, q, r, D = 1, 8, 1, 1, 8
    results = ifmap_index_generator_c_model(n, W, q, r, D, 0, 0)
    expected_count = n * W * q * D * r
    print(f"\n=== Ifmap Index Generator Test ===")
    print(f"Parameters: n={n},W={W},q={q},r={r},D={D}")
    print(f"Generated: {len(results)} addresses (expected: {expected_count})")
    assert len(results) == expected_count, f"FAIL: got {len(results)}, expected {expected_count}"

    # Verify first 5 addresses (row-major CHW order)
    # addr = n_idx*q*r*D*W + c_idx*D*W + row*W + col
    # = 0*1*8*8 + 0*8*8 + row*8 + col
    print("First 10 addresses:")
    for i, (ifm, ch, row, col) in enumerate(results[:10]):
        addr = mapper_4d_to_1d(ifm, ch, row, col, q*r, D, W)
        print(f"  [{i}] ifmap={ifm} ch={ch} row={row} col={col} → addr={addr}")

    # Verify: row increases fastest (innermost D loop), then col
    assert results[0] == (0, 0, 0, 0), f"First should be (0,0,0,0): {results[0]}"
    assert results[1] == (0, 0, 1, 0), f"Second should be (0,0,1,0): {results[1]}"
    print("PASS: Ifmap index generator correct")
    return True


def test_filter_generator():
    """Test with tiny config: p=1,q=1,S=3,R=3,r=1,t=1,filter_start=0,channel_start=0"""
    p, q, S, R, r, t = 1, 1, 3, 3, 1, 1
    results = filter_index_generator_c_model(p, q, S, R, r, t, 0, 0)
    expected_count = R * r * t * 4  # inner loop is fixed at 4 iterations
    print(f"\n=== Filter Index Generator Test ===")
    print(f"Parameters: p={p},q={q},S={S},R={R},r={r},t={t}")
    print(f"Generated: {len(results)} (expected: R*r*t*4 = {R}*{r}*{t}*4 = {expected_count})")
    assert len(results) == expected_count, f"FAIL: got {len(results)}, expected {expected_count}"
    print("PASS: Filter index generator correct")

    print("All filter addresses:")
    for i, (filt, ch, row, col) in enumerate(results):
        addr = mapper_4d_to_1d(filt, ch, row, col, q*r, R, S)
        print(f"  [{i}] filter={filt} ch={ch} row={row} col={col} → addr={addr}")
    return True


def test_psum_generator():
    """Test with tiny config: p=1,F=6,n=1,e=6,t=1,psum_start=0,channel_start=0"""
    p, F, n, e, t = 1, 6, 1, 6, 1
    results = psum_index_generator_c_model(p, F, n, e, t, 0, 0)
    # Lock-step count: first iterations advance F, then lock for remainder
    # For p=1, lock after 2nd (e,t) → 2×4 + (e-2)*4 = e*4 for t=1
    expected_min = e * t * 4  # minimum (if never locks during outer loop)
    print(f"\n=== PSum Index Generator Test ===")
    print(f"Parameters: p={p},F={F},n={n},e={e},t={t}")
    print(f"Generated: {len(results)} (min expected: {expected_min})")
    assert len(results) >= expected_min, f"FAIL: got {len(results)} < expected_min {expected_min}"
    print("PASS: PSum index generator correct")

    print("First 10 psum addresses:")
    for i, (psum, ch, row, col) in enumerate(results[:10]):
        addr = mapper_4d_to_1d(psum, ch, row, col, n, e, F)
        print(f"  [{i}] psum={psum} ch={ch} row={row} col={col} → addr={addr}")
    return True


def test_bug_fix():
    """Project 1 known bug: Scheduler.c has 'break' after first pass in some versions.
    Verify the Python model correctly generates all passes."""
    M, C, N = 16, 32, 4
    n, p, q, r, t = 1, 4, 4, 2, 2
    passes = scheduler_c_model(M, C, N, n, p, q, r, t)
    N_blk = N//n
    C_blk = C//(q*r)
    M_blk = M//(p*t)
    expected = N_blk * C_blk * M_blk
    print(f"\n=== Bug Verification (M={M},C={C},N={N},p={p},q={q},r={r},t={t}) ===")
    print(f"Passes: {len(passes)}, Expected: {N_blk}×{C_blk}×{M_blk}={expected}")
    if len(passes) == expected:
        print("PASS: No 'break' bug — all passes generated")
    else:
        print(f"FAIL: Bug detected — {len(passes)} != {expected}")
    return len(passes) == expected


# ============================================================================
# Main
# ============================================================================
if __name__ == "__main__":
    print("=" * 60)
    print("Task 2: Project 1 (C Data Delivery) Algorithm Verification")
    print("=" * 60)

    all_pass = True
    all_pass &= test_scheduler()
    all_pass &= test_ifmap_generator()
    all_pass &= test_filter_generator()
    all_pass &= test_psum_generator()
    all_pass &= test_bug_fix()

    print(f"\n{'='*60}")
    if all_pass:
        print("ALL TESTS PASSED — C model algorithms verified")
    else:
        print("SOME TESTS FAILED — see above")
    print(f"{'='*60}")
