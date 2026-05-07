"""
PE Array comprehensive test.

Architecture: 3×3 systolic array, broadcast data, RS start propagation.

Test 1: Same data/filter on all rows → vertical accumulation.
Test 2: Different data/filter per cycle (correct RS emulation) → 2D conv.
Test 3: Selective new_in_data (only PEs on the start propagation path).
Test 4: Verify non-first-column PEs also produce results (partially meaningful).
"""
import sys
sys.path.insert(0, 'H:/cc_project/rs_core/py')
from pe_array import PEArray


def print_full_state(array, step):
    """Print complete grid state."""
    print(f"\n{'='*60}")
    print(f"  Step {step}")
    print(f"{'='*60}")
    for r in range(3):
        for c in range(3):
            pe = array.grid[r][c]
            print(f"  PE({r},{c}): state={pe.state} iter={pe.iter} "
                  f"start={pe.start} new_in_data={pe.new_in_data} "
                  f"out_start={pe.out_start} finished={pe.finished}")
            print(f"           data={list(pe.data)} filt={list(pe.filt)} "
                  f"result={list(pe.result)}")
    print(f"  Array: finished={array.finished} output={array.output}")


def set_all_new_in_data(array, val):
    """Set new_in_data for all PEs."""
    for r in range(3):
        for c in range(3):
            array.grid[r][c].new_in_data = val


def test_same_data_all_rows():
    """Test 1: Same data/filter, all new_in_data=1 — simplest test."""
    print("=" * 60)
    print("TEST 1: Same data/filter on all rows")
    print("=" * 60)

    data_port = [1, 2, 3, 4, 5]
    filter_port = [1, 2, 3]
    array = PEArray(3, data_port, filter_port)

    # All PEs can latch data
    set_all_new_in_data(array, 1)
    # Start at top-left
    array.grid[0][0].start = 1

    for step in range(10):
        array.process()
        if step >= 4 and array.finished:
            print(f"  Finished at step {step+1}")
            break

    # Expected: bottom-left PE(2,0) result = [14+14+14, 20+20+20, 26+26+26] = [42, 60, 78]
    # Because all rows get same data/filter, each row adds same MAC result
    expected = [42, 60, 78]
    ok = array.grid[2][0].result == expected
    print(f"  PE(2,0) result: {array.grid[2][0].result}")
    print(f"  Expected: {expected}")
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


def test_different_data_per_cycle():
    """Test 2: Different data/filter each cycle, all new_in_data=1 — mimics RS."""
    print("\n" + "=" * 60)
    print("TEST 2: Different data/filter rows (all PEs latch)")
    print("=" * 60)

    data_port = [0] * 5
    filter_port = [0] * 3
    array = PEArray(3, data_port, filter_port)

    data_rows = [
        [1,  2,  3,  4,  5],
        [6,  7,  8,  9,  10],
        [11, 12, 13, 14, 15],
    ]
    filter_rows = [
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
    ]

    for step in range(10):
        if step < 3:
            data_port[:] = data_rows[step]
            filter_port[:] = filter_rows[step]
            set_all_new_in_data(array, 1)
            if step == 0:
                array.grid[0][0].start = 1
        else:
            set_all_new_in_data(array, 0)

        array.process()

        if array.finished:
            print(f"  Finished at step {step+1}")
            break

    # PE(2,0) should produce [411, 456, 501]
    expected = [411, 456, 501]
    ok = array.grid[2][0].result == expected
    print(f"  PE(2,0) result: {array.grid[2][0].result}")
    print(f"  Expected: {expected}")
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


def test_selective_new_in_data():
    """Test 3: Only PEs on start-propagation path get new_in_data."""
    print("\n" + "=" * 60)
    print("TEST 3: Selective new_in_data (hardware-accurate)")
    print("=" * 60)

    data_port = [0] * 5
    filter_port = [0] * 3
    array = PEArray(3, data_port, filter_port)

    data_rows = [
        [1,  2,  3,  4,  5],
        [6,  7,  8,  9,  10],
        [11, 12, 13, 14, 15],
    ]
    filter_rows = [
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
    ]

    for step in range(10):
        # Update data bus each cycle for first 3 cycles
        if step < 3:
            data_port[:] = data_rows[step]
            filter_port[:] = filter_rows[step]

        # Clear all new_in_data
        set_all_new_in_data(array, 0)

        if step == 0:
            # Only PE(0,0) gets start and new_in_data
            array.grid[0][0].new_in_data = 1
            array.grid[0][0].start = 1
        elif step == 1:
            # PE(0,1) and PE(1,0) receive propagated start, need new data
            array.grid[0][1].new_in_data = 1
            array.grid[1][0].new_in_data = 1
        elif step == 2:
            # PE(0,2), PE(1,1), PE(2,0) on the diagonal
            array.grid[0][2].new_in_data = 1
            array.grid[1][1].new_in_data = 1
            array.grid[2][0].new_in_data = 1

        array.process()

        if array.finished:
            print(f"  Finished at step {step+1}")
            break

    expected = [411, 456, 501]
    ok = array.grid[2][0].result == expected
    print(f"  PE(2,0) result: {array.grid[2][0].result}")
    print(f"  Expected: {expected}")

    # Also verify non-first-column PEs have been "activated" but may produce
    # less meaningful results since they get the same broadcast data
    print(f"  PE(2,1) result: {array.grid[2][1].result}")
    print(f"  PE(2,2) result: {array.grid[2][2].result}")
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


def test_array_output_signal():
    """Test 4: Verify array.finished and array.output timing."""
    print("\n" + "=" * 60)
    print("TEST 4: Array output timing")
    print("=" * 60)

    data_port = [1, 2, 3, 4, 5]
    filter_port = [1, 1, 1]
    array = PEArray(3, data_port, filter_port)

    # This should produce result [42, 60, 78] (3 × [14,20,26] = [6*3,9*3,12*3] wait...
    # Actually with same data: each PE produces [6,9,12], accumulated across 3 rows = [18,27,36])
    set_all_new_in_data(array, 1)
    array.grid[0][0].start = 1

    for step in range(10):
        array.process()
        if step < 5:
            print(f"  Step {step+1}: finished={array.finished} output={array.output}")
        if array.finished:
            print(f"  Finished at step {step+1}: finished={array.finished} output={array.output}")
            break

    expected = [18, 27, 36]  # [6*3, 9*3, 12*3]
    ok = array.output == expected
    print(f"  Array output: {array.output}, expected: {expected}")
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


if __name__ == "__main__":
    all_ok = True
    all_ok &= test_same_data_all_rows()
    all_ok &= test_different_data_per_cycle()
    all_ok &= test_selective_new_in_data()
    all_ok &= test_array_output_signal()

    print("\n" + "=" * 60)
    print(f"OVERALL: {'ALL PASSED' if all_ok else 'SOME FAILED'}")
    print("=" * 60)
