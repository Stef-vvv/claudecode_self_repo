"""
PE module comprehensive test.
Tests:
  1. Basic MAC: single data row, single filter row
  2. MAC+ACC: accumulation of upstream partial sums
  3. Timing: out_start duration and sequence
  4. Data latching: new_in_data controls data capture
  5. Full pipeline: start -> MAC(3) -> ACC(1) -> DONE(1) -> IDLE
  6. Continuity: back-to-back operations
"""
import sys
sys.path.insert(0, 'H:/cc_project/rs_core/py')
from pe import PE

def test_basic_mac():
    """Test 1: Basic sliding-window MAC computation."""
    print("=" * 50)
    print("TEST 1: Basic MAC")
    print("=" * 50)
    pe = PE()

    pe.in_data = [1, 2, 3, 4, 5]
    pe.in_filter = [1, 2, 3]
    pe.in_result = [0, 0, 0]
    pe.start = 1
    pe.new_in_data = 1

    # 4 cycles: start+M0, M1, M2, ACC
    for i in range(4):
        pe.process_one()

    expected = [14, 20, 26]  # dot([1,2,3],[1,2,3])=14, dot([2,3,4],[1,2,3])=20, dot([3,4,5],[1,2,3])=26
    ok = pe.result == expected and pe.finished == 1
    print(f"  result = {pe.result}, expected = {expected}")
    print(f"  finished = {pe.finished}")
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


def test_mac_with_accumulation():
    """Test 2: MAC + upstream partial sum accumulation."""
    print("\n" + "=" * 50)
    print("TEST 2: MAC + Accumulation")
    print("=" * 50)
    pe = PE()

    pe.in_data = [0, 1, 2, 3, 4]
    pe.in_filter = [4, 3, 2]
    pe.in_result = [10, 20, 30]  # upstream partial sums
    pe.start = 1
    pe.new_in_data = 1

    for i in range(4):
        pe.process_one()

    # dot([0,1,2],[4,3,2])=7, dot([1,2,3],[4,3,2])=16, dot([2,3,4],[4,3,2])=25
    # after ACC: 7+10=17, 16+20=36, 25+30=55
    expected = [17, 36, 55]
    ok = pe.result == expected and pe.finished == 1
    print(f"  result = {pe.result}, expected = {expected}")
    print(f"  finished = {pe.finished}")
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


def test_timing():
    """Test 3: Verify out_start timing and state transitions."""
    print("\n" + "=" * 50)
    print("TEST 3: Timing / State Transitions")
    print("=" * 50)
    pe = PE()

    pe.in_data = [1, 2, 3, 4, 5]
    pe.in_filter = [1, 1, 1]
    pe.in_result = [0, 0, 0]
    pe.start = 1
    pe.new_in_data = 1

    # Cycle 0: IDLE -> MAC(iter0), out_start=1
    pe.process_one()
    s0 = (pe.state, pe.iter, pe.out_start, pe.finished, list(pe.result))
    print(f"  Cycle 0: state={s0[0]}, iter={s0[1]}, out_start={s0[2]}, finished={s0[3]}, result={s0[4]}")
    ok0 = (s0 == (1, 1, 1, 0, [6, 0, 0]))

    # Cycle 1: MAC(iter1), out_start=0
    pe.process_one()
    s1 = (pe.state, pe.iter, pe.out_start, pe.finished, list(pe.result))
    print(f"  Cycle 1: state={s1[0]}, iter={s1[1]}, out_start={s1[2]}, finished={s1[3]}, result={s1[4]}")
    ok1 = (s1 == (1, 2, 0, 0, [6, 9, 0]))

    # Cycle 2: MAC(iter2), state->ACC
    pe.process_one()
    s2 = (pe.state, pe.iter, pe.out_start, pe.finished, list(pe.result))
    print(f"  Cycle 2: state={s2[0]}, iter={s2[1]}, out_start={s2[2]}, finished={s2[3]}, result={s2[4]}")
    ok2 = (s2 == (2, 0, 0, 0, [6, 9, 12]))

    # Cycle 3: ACC -> DONE
    pe.process_one()
    s3 = (pe.state, pe.iter, pe.out_start, pe.finished, list(pe.result))
    print(f"  Cycle 3: state={s3[0]}, iter={s3[1]}, out_start={s3[2]}, finished={s3[3]}, result={s3[4]}")
    ok3 = (s3 == (3, 0, 0, 1, [6, 9, 12]))

    # Cycle 4: DONE -> IDLE
    pe.process_one()
    s4 = (pe.state, pe.iter, pe.out_start, pe.finished, list(pe.result))
    print(f"  Cycle 4: state={s4[0]}, iter={s4[1]}, out_start={s4[2]}, finished={s4[3]}, result={s4[4]}")
    ok4 = (s4 == (0, 0, 0, 0, [6, 9, 12]))

    ok = ok0 and ok1 and ok2 and ok3 and ok4
    print(f"  {'PASS' if ok else 'FAIL'}")
    if not ok:
        print(f"  Failures: ok0={ok0} ok1={ok1} ok2={ok2} ok3={ok3} ok4={ok4}")
    return ok


def test_data_latching():
    """Test 4: new_in_data controls whether data is latched."""
    print("\n" + "=" * 50)
    print("TEST 4: Data Latching (new_in_data)")
    print("=" * 50)
    pe = PE()

    # First operation: latch data0
    pe.in_data = [1, 2, 3, 4, 5]
    pe.in_filter = [1, 1, 1]
    pe.in_result = [0, 0, 0]
    pe.start = 1
    pe.new_in_data = 1
    for i in range(5):  # Complete full cycle back to IDLE
        pe.process_one()

    ok0 = (pe.result == [6, 9, 12]) and (pe.state == 0)
    print(f"  First op result: {pe.result}, state={pe.state} — {'OK' if ok0 else 'FAIL'}")

    # Second operation: start without new_in_data — should keep OLD data
    pe.in_data = [9, 9, 9, 9, 9]  # This should NOT be latched
    pe.in_filter = [2, 2, 2]       # This should NOT be latched
    pe.in_result = [100, 100, 100]
    pe.start = 1
    pe.new_in_data = 0  # No data update!
    for i in range(4):
        pe.process_one()

    # Should use OLD data [1,2,3,4,5] and OLD filter [1,1,1], plus accumulate [100,100,100]
    # result = [6+100, 9+100, 12+100] = [106, 109, 112]
    ok1 = (pe.result == [106, 109, 112])
    print(f"  Second op result: {pe.result}, expected [106, 109, 112] — {'OK' if ok1 else 'FAIL'}")

    ok = ok0 and ok1
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


def test_back_to_back():
    """Test 5: Back-to-back operations with new data each time."""
    print("\n" + "=" * 50)
    print("TEST 5: Back-to-Back Operations")
    print("=" * 50)

    pe = PE()
    results = []

    data_sets = [
        ([1, 2, 3, 4, 5], [1, 1, 1]),       # result = [6, 9, 12]
        ([2, 3, 4, 5, 6], [2, 2, 2]),       # result = [18, 24, 30]
        ([0, 1, 2, 3, 4], [1, 2, 3]),       # result = [8, 14, 20]
    ]

    for data, filt in data_sets:
        pe.in_data = data
        pe.in_filter = filt
        pe.in_result = [0, 0, 0]
        pe.start = 1
        pe.new_in_data = 1
        for i in range(5):  # Complete full cycle
            pe.process_one()
        results.append(list(pe.result))

    expected = [[6, 9, 12], [18, 24, 30], [8, 14, 20]]
    ok = results == expected
    print(f"  Results: {results}")
    print(f"  Expected: {expected}")
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


def test_partial_propagation():
    """Test 6: Simulate column accumulation (3 PEs in a column)."""
    print("\n" + "=" * 50)
    print("TEST 6: Column Accumulation (3 PEs in column)")
    print("=" * 50)

    # Simulate 3 PEs stacked vertically, each receiving:
    # - Broadcast data (same for all)
    # - Filter from left (propagated rightward)
    # - Start signal from top-left (propagated diagonally)
    #
    # PE(0,0): data=[1,2,3,4,5], filter=[1,2,3], psum_in=[0,0,0]
    # PE(1,0): data=[6,7,8,9,10], filter=[4,5,6], psum_in=PE(0,0).result
    # PE(2,0): data=[11,12,13,14,15], filter=[7,8,9], psum_in=PE(1,0).result

    pe0 = PE()
    pe0.in_data = [1, 2, 3, 4, 5]
    pe0.in_filter = [1, 2, 3]
    pe0.in_result = [0, 0, 0]
    pe0.start = 1
    pe0.new_in_data = 1
    for i in range(5):
        pe0.process_one()

    pe1 = PE()
    pe1.in_data = [6, 7, 8, 9, 10]
    pe1.in_filter = [4, 5, 6]
    pe1.in_result = pe0.result  # Accumulate from PE0
    pe1.start = 1
    pe1.new_in_data = 1
    for i in range(5):
        pe1.process_one()

    pe2 = PE()
    pe2.in_data = [11, 12, 13, 14, 15]
    pe2.in_filter = [7, 8, 9]
    pe2.in_result = pe1.result  # Accumulate from PE1
    pe2.start = 1
    pe2.new_in_data = 1
    for i in range(5):
        pe2.process_one()

    print(f"  PE(0,0) result = {pe0.result}")   # [14, 20, 26]
    print(f"  PE(1,0) result = {pe1.result}")   # [14+107, 20+122, 26+137] = [121, 142, 163]
    print(f"  PE(2,0) result = {pe2.result}")   # [121+290, 142+314, 163+338] = [411, 456, 501]
    expected_pe2 = [411, 456, 501]
    ok = pe2.result == expected_pe2
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


if __name__ == "__main__":
    all_ok = True
    all_ok &= test_basic_mac()
    all_ok &= test_mac_with_accumulation()
    all_ok &= test_timing()
    all_ok &= test_data_latching()
    all_ok &= test_back_to_back()
    all_ok &= test_partial_propagation()

    print("\n" + "=" * 50)
    print(f"OVERALL: {'ALL PASSED' if all_ok else 'SOME FAILED'}")
    print("=" * 50)
