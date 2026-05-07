"""
Scheduler integration test.
Tests scheduler-driven PE array operation for one conv tile.
"""
import sys
sys.path.insert(0, 'H:/cc_project/rs_core/py')
from bram import BRAM
from scheduler import Scheduler


def test_single_tile():
    """Test: Scheduler runs one 3×3 conv tile through PE array."""
    print("=" * 60)
    print("TEST: Single Tile Convolution")
    print("=" * 60)

    input_bram = BRAM(1000)
    filter_bram = BRAM(1000)
    sched = Scheduler(input_bram, filter_bram, n_arrays=1)

    # 3 rows of ifmap (5 elements each for sliding window)
    ifmap_rows = [
        [1,  2,  3,  4,  5],
        [6,  7,  8,  9,  10],
        [11, 12, 13, 14, 15],
    ]
    filter_rows = [
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
    ]

    result = sched.run_one_tile(ifmap_rows, filter_rows)
    print(f"  Result: {result}")
    print(f"  Total cycles: {sched.total_cycles}")

    expected = [411, 456, 501]
    ok = result == expected
    print(f"  Expected: {expected}")
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


def test_simple_tile():
    """Test: Simple all-ones filter to verify correct timing."""
    print("\n" + "=" * 60)
    print("TEST: Simple Tile (all-ones filter)")
    print("=" * 60)

    input_bram = BRAM(1000)
    filter_bram = BRAM(1000)
    sched = Scheduler(input_bram, filter_bram, n_arrays=1)

    ifmap_rows = [
        [1, 2, 3, 4, 5],
        [1, 2, 3, 4, 5],
        [1, 2, 3, 4, 5],
    ]
    filter_rows = [
        [1, 1, 1],
        [1, 1, 1],
        [1, 1, 1],
    ]

    result = sched.run_one_tile(ifmap_rows, filter_rows)
    print(f"  Result: {result}")

    # Each row: dot = [6, 9, 12], accumulated across 3 rows = [18, 27, 36]
    expected = [18, 27, 36]
    ok = result == expected
    print(f"  Expected: {expected}")
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


def test_back_to_back_tiles():
    """Test: Two tiles back-to-back through the same scheduler."""
    print("\n" + "=" * 60)
    print("TEST: Back-to-Back Tiles")
    print("=" * 60)

    input_bram = BRAM(1000)
    filter_bram = BRAM(1000)
    sched = Scheduler(input_bram, filter_bram, n_arrays=1)

    # First tile
    r1 = sched.run_one_tile(
        [[1, 2, 3, 4, 5], [6, 7, 8, 9, 10], [11, 12, 13, 14, 15]],
        [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
    )
    print(f"  Tile 1 result: {r1}")

    # Second tile (different data)
    r2 = sched.run_one_tile(
        [[2, 3, 4, 5, 6], [3, 4, 5, 6, 7], [4, 5, 6, 7, 8]],
        [[1, 1, 1], [1, 1, 1], [1, 1, 1]]
    )
    print(f"  Tile 2 result: {r2}")

    ok1 = (r1 == [411, 456, 501])
    ok2 = (r2 == [36, 45, 54])  # dot per row=[9,12,15], ×3=[27,36,45]... wait let me recalc
    # row0: [2,3,4]*[1,1,1] [3,4,5]*[1,1,1] [4,5,6]*[1,1,1] = 9, 12, 15
    # row1: [3,4,5]*[1,1,1] [4,5,6]*[1,1,1] [5,6,7]*[1,1,1] = 12, 15, 18
    # row2: [4,5,6]*[1,1,1] [5,6,7]*[1,1,1] [6,7,8]*[1,1,1] = 15, 18, 21
    # accumulated: [9+12+15, 12+15+18, 15+18+21] = [36, 45, 54]

    ok = ok1 and ok2
    print(f"  Expected Tile 1: [411, 456, 501]")
    print(f"  Expected Tile 2: [36, 45, 54]")
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


if __name__ == "__main__":
    all_ok = True
    all_ok &= test_single_tile()
    all_ok &= test_simple_tile()
    all_ok &= test_back_to_back_tiles()

    print("\n" + "=" * 60)
    print(f"OVERALL: {'ALL PASSED' if all_ok else 'SOME FAILED'}")
    print("=" * 60)
