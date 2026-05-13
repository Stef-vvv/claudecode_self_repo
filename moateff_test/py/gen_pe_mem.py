#!/usr/bin/env python3
"""
Generate .mem files for PE standalone verification.

Small test case: 1D convolution
  W=5 (ifmap width), S=3 (kernel size), F=3 (ofmap width)
  U=1 (stride), n=1 (input channels), p=1 (output channels), q=1

The PE computes (Q3.13 fixed-point, but we use pure integers for simplicity):
  opsum[k] = sum(ifmap[k*U + i] * filter[i], i=0..S-1) + ipsum[k]

Output: ifmap_data.mem, filter_data.mem, ipsum_data.mem, expected_output.mem
Format: $readmemb-compatible binary text (one 16-bit string per line for ifmap;
        four 16-bit groups with '_' separators per line for 64-bit packed entries).
"""

import os
import sys


def int_to_bin_16bit(val: int) -> str:
    """
    Convert signed integer to 16-bit two's complement binary string.
    Handles values in range [-32768, 32767].
    """
    clamped = val & 0xFFFF
    return format(clamped, '016b')


def pack_64bit(values: list) -> str:
    """
    Pack up to 4 signed 16-bit values into one 64-bit .mem line.

    Format matches the reference C code (Convert_to_binary.c):
      lines[3]_lines[2]_lines[1]_lines[0]  (REVERSED order)

    When read by $readmemb as a 64-bit binary value, the FIFO unpacks
    them back into the original order (mem[wr_addr+0] gets lines[0],
    mem[wr_addr+1] gets lines[1], etc.).
    """
    if len(values) > 4:
        raise ValueError(f"pack_64bit: at most 4 values, got {len(values)}")
    padded = list(values) + [0] * (4 - len(values))
    bins = [int_to_bin_16bit(v) for v in padded]
    # Reversed: lines[3]_lines[2]_lines[1]_lines[0]
    return f"{bins[3]}_{bins[2]}_{bins[1]}_{bins[0]}"


def compute_1d_conv(ifmap: list, filter_vals: list, S: int,
                     U: int, F: int, ipsum: list) -> list:
    """
    Compute 1D convolution: opsum[k] = sum(ifmap[k*U+i]*filter[i]) + ipsum[k]
    """
    outputs = []
    for k in range(F):
        conv = 0
        for i in range(S):
            conv += ifmap[k * U + i] * filter_vals[i]
        outputs.append(conv + ipsum[k])
    return outputs


def pad_cycles_from_V(V: int, V_width: int = 2) -> int:
    """
    Compute number of PADDING state cycles given V value.

    V = p[1:0] * F[1:0]  (2-bit multiplication)
    The PADDING state asserts pad=1 until V_crnt wraps to 0.
    V_crnt is V_WIDTH bits, so it wraps at 2**V_width.
    """
    mod = 1 << V_width  # 4 for V_width=2
    V_mod = V % mod
    if V_mod == 0:
        return 0
    return (mod - V_mod) % mod


def main():
    # ============================================================
    # Test parameters
    # ============================================================
    W = 5   # ifmap width
    S = 3   # filter / kernel size
    F = 3   # ofmap width = (W - S) / U + 1
    U = 1   # stride
    n = 1   # input channels
    p = 1   # output channels
    q = 1   # q parameter (rows per tile)

    # V = p[1:0] * F[1:0] controls padding cycles
    V = (p & 0x3) * (F & 0x3)

    print("=" * 60)
    print("PE Standalone Test Data Generator")
    print("=" * 60)
    print(f"Parameters: W={W}, S={S}, F={F}, U={U}, n={n}, p={p}, q={q}")
    print(f"V = p[1:0]*F[1:0] = {p&0x3}*{F&0x3} = {V}")

    # ============================================================
    # Test data (non-zero, simple patterns)
    # ============================================================
    ifmap = [1, 2, 3, 4, 5]
    filter_vals = [2, 3, 4]
    ipsum = [10, 20, 30]

    print(f"\nifmap  : {ifmap}")
    print(f"filter : {filter_vals}")
    print(f"ipsum  : {ipsum}")

    # ============================================================
    # Compute expected outputs
    # ============================================================
    conv_outputs = compute_1d_conv(ifmap, filter_vals, S, U, F, ipsum)

    # Padding outputs
    pc = pad_cycles_from_V(V)
    total_outputs = F * p * n + pc * p * n
    # Pad to fill the last packed 64-bit entry
    all_outputs = list(conv_outputs) + [0] * (total_outputs - len(conv_outputs))

    print(f"\npad_cycles = {pc}")
    print(f"total outputs = {total_outputs}  "
          f"(conv={F*p*n}, pad={pc*p*n})")
    print(f"expected outputs: {all_outputs}")

    # ============================================================
    # Show detailed computation
    # ============================================================
    print(f"\n{'='*60}")
    print("Computation Details")
    print(f"{'='*60}")
    for k in range(F):
        terms = [f"{ifmap[k*U+i]}*{filter_vals[i]}" for i in range(S)]
        conv = sum(ifmap[k*U+i] * filter_vals[i] for i in range(S))
        total = conv + ipsum[k]
        print(f"  opsum[{k}] = {' + '.join(terms)} + ipsum[{k}]")
        print(f"            = {conv} + {ipsum[k]} = {total}")
    if pc > 0:
        print(f"  opsum[{F}..{F+pc-1}] = 0  (padding)")

    # ============================================================
    # Compute .mem entry counts
    # ============================================================
    ifmap_entries = n * W * q
    filter_entries = (p * q * S + 3) // 4
    ipsum_entries = (p * n * F + 3) // 4
    expected_entries = (p * n * F + 3) // 4

    print(f"\n{'='*60}")
    print(".mem File Layout")
    print(f"{'='*60}")
    print(f"  ifmap_data.mem      : {ifmap_entries:>3d} lines (16-bit each)")
    print(f"  filter_data.mem     : {filter_entries:>3d} lines (64-bit packed)")
    print(f"  ipsum_data.mem      : {ipsum_entries:>3d} lines (64-bit packed)")
    print(f"  expected_output.mem : {expected_entries:>3d} lines (64-bit packed)")

    # ============================================================
    # Write .mem files (in current working directory)
    # ============================================================
    out_dir = os.getcwd()
    print(f"\nWriting .mem files to: {out_dir}")

    # -- ifmap_data.mem --
    with open(os.path.join(out_dir, "ifmap_data.mem"), "w") as f:
        for v in ifmap:
            f.write(int_to_bin_16bit(v) + "\n")
    print(f"  [OK] ifmap_data.mem  ({len(ifmap)} values)")

    # -- filter_data.mem --
    with open(os.path.join(out_dir, "filter_data.mem"), "w") as f:
        for entry in range(filter_entries):
            start = entry * 4
            vals = filter_vals[start:start + 4]
            f.write(pack_64bit(vals) + "\n")
    print(f"  [OK] filter_data.mem ({filter_entries} entry/entries)")

    # -- ipsum_data.mem --
    with open(os.path.join(out_dir, "ipsum_data.mem"), "w") as f:
        for entry in range(ipsum_entries):
            start = entry * 4
            vals = ipsum[start:start + 4]
            f.write(pack_64bit(vals) + "\n")
    print(f"  [OK] ipsum_data.mem  ({ipsum_entries} entry/entries)")

    # -- expected_output.mem --
    with open(os.path.join(out_dir, "expected_output.mem"), "w") as f:
        for entry in range(expected_entries):
            start = entry * 4
            vals = all_outputs[start:start + 4]
            f.write(pack_64bit(vals) + "\n")
    print(f"  [OK] expected_output.mem ({expected_entries} entry/entries)")

    # ============================================================
    # Preview the generated content
    # ============================================================
    print(f"\n{'='*60}")
    print("Generated .mem Content Preview")
    print(f"{'='*60}")

    print("\n--- ifmap_data.mem ---")
    for v in ifmap:
        print(f"  {int_to_bin_16bit(v)}  (={v})")

    print("\n--- filter_data.mem ---")
    print(f"  {pack_64bit(filter_vals[:4])}")
    print(f"  Unpacked: {filter_vals[:4]}")

    print("\n--- ipsum_data.mem ---")
    print(f"  {pack_64bit(ipsum[:4])}")
    print(f"  Unpacked: {ipsum[:4]}")

    print("\n--- expected_output.mem ---")
    print(f"  {pack_64bit(all_outputs[:4])}")
    print(f"  Unpacked: {all_outputs[:4]}")

    print(f"\n{'='*60}")
    print("Done. Run the simulation with: bash run_pe.sh")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
