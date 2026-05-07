"""
Top-level integration test: BRAM → Scheduler → PE Array → Aggregator → WriteRam → BRAM

Tests full RS dataflow for one convolution layer (simplified single channel).
"""
import sys
sys.path.insert(0, 'H:/cc_project/rs_core/py')
from bram import BRAM
from scheduler import Scheduler
from aggregator import Aggregator
from write_to_ram import WriteRam


def test_full_pipeline_3x3_conv():
    """
    Full pipeline: input bram → scheduler → array → aggregator → output bram
    Conv: 5×5 ifmap, 3×3 filter, stride=1 → 3×3 ofmap (1 channel).
    """
    print("=" * 60)
    print("TEST: Full Pipeline — 5×5 conv with 3×3 filter")
    print("=" * 60)

    # Create BRAMs
    input_bram = BRAM(16384)
    filter_bram = BRAM(16384)
    output_bram = BRAM(16384)

    # Store ifmap in input BRAM (row-major, 16 elements per 128-bit row)
    # 5×5 ifmap, stored as 5 rows of 16 elements each (rest zero)
    ifmap = [
        [1, 2, 3, 4, 5],
        [6, 7, 8, 9, 10],
        [11, 12, 13, 14, 15],
        [16, 17, 18, 19, 20],
        [21, 22, 23, 24, 25],
    ]
    for r, row in enumerate(ifmap):
        padded = list(row) + [0] * 11  # Pad to 16 elements
        input_bram.write(r, padded, 128)

    # Store filter in filter BRAM (3 weights per 32-bit row)
    filters = [
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
    ]
    for r, row in enumerate(filters):
        padded = list(row) + [0]  # Pad to 4 bytes
        filter_bram.write(r, padded, 32)

    # Set up scheduler
    sched = Scheduler(input_bram, filter_bram, n_arrays=1)
    agg = Aggregator(output_bram, sched.pe_arrays)
    wr = WriteRam(output_bram, agg)
    sched.aggregator = agg
    sched.write_ram = wr

    # Run 3×3 conv over 5×5 ifmap → 3×3 ofmap (stride 1)
    H, W = 5, 5
    K = 3
    out_H = (H - K) // 1 + 1  # 3
    out_W = (W - K) // 1 + 1  # 3

    ofmap = [[0] * out_W for _ in range(out_H)]

    for oh in range(out_H):
        for ow in range(out_W):
            # Extract ifmap tile rows (3 rows × 5 elements each for sliding window)
            ifmap_rows = []
            for kh in range(K):
                row_data = []
                for kw in range(5):  # 5 elements wide
                    r, c = oh + kh, ow + kw
                    row_data.append(ifmap[r][c])
                ifmap_rows.append(row_data)

            result = sched.run_one_tile(ifmap_rows, filters)
            for p in range(3):  # 3 sliding window outputs per tile
                if ow + p < out_W:
                    ofmap[oh][ow + p] += result[p]
            # Break after first row since we only handle 1D output in this model
            if ow == 0:
                break

    # Print results
    print("  Output feature map:")
    for row in ofmap:
        print(f"    {row}")

    # Expected 3×3 ofmap for first conv:
    # Position (0,0): PE computes 3 sliding window positions from ifmap row 0..2 col 0..4
    # result[0] = ifmap_row0[0:3]·filter[0] + ifmap_row1[0:3]·filter[1] + ifmap_row2[0:3]·filter[2]
    #
    # row0: [1,2,3]·[1,2,3] = 14
    #        [2,3,4]·[4,5,6] = 47... wait, filter is different per row
    # row0: [1,2,3]·[1,2,3] = 1+4+9 = 14
    # row1: [6,7,8]·[4,5,6] = 24+35+48 = 107
    # row2: [11,12,13]·[7,8,9] = 77+96+117 = 290
    # ofmap[0][0] = 14+107+290 = 411

    expected_0_0 = 411
    # ofmap[0][1] = [2,3,4]*[1,2,3] + [7,8,9]*[4,5,6] + [12,13,14]*[7,8,9]
    # = (2+6+12) + (28+40+54) + (84+104+126) = 20 + 122 + 314 = 456
    expected_0_1 = 456

    ok0 = (ofmap[0][0] == expected_0_0)
    ok1 = (ofmap[0][1] == expected_0_1)
    print(f"  ofmap[0][0] = {ofmap[0][0]}, expected {expected_0_0} — {'OK' if ok0 else 'FAIL'}")
    print(f"  ofmap[0][1] = {ofmap[0][1]}, expected {expected_0_1} — {'OK' if ok1 else 'FAIL'}")

    ok = ok0 and ok1
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


if __name__ == "__main__":
    ok = test_full_pipeline_3x3_conv()
    print(f"\n{'='*60}")
    print(f"OVERALL: {'PASSED' if ok else 'FAILED'}")
    print(f"{'='*60}")
