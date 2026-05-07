"""
PE 单元测试: 手工可验证的小测试用例.
验证: 基本MAC, 时序, 数据锁存, 部分和累加, 背靠背操作.
"""
import sys
sys.path.insert(0, 'H:/cc_project/py_project')
from pe import PE


def print_result(name, actual, expected, ok):
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] {name}: actual={actual}, expected={expected}")


def test_basic_mac():
    """Test1: data=[1,2,3,4,5], filter=[1,2,3], psum=[0,0,0]
    dot(0): 1*1+2*2+3*3 = 14
    dot(1): 2*1+3*2+4*3 = 20
    dot(2): 3*1+4*2+5*3 = 26
    期望: result=[14,20,26], finished=1 (4拍后)
    """
    print("=" * 50)
    print("TEST 1: Basic MAC")
    pe = PE(3)
    pe.in_data = [1, 2, 3, 4, 5]
    pe.in_filter = [1, 2, 3]
    pe.in_result = [0, 0, 0, 0, 0]
    pe.start = [1]
    pe.new_in_data = [1]

    for i in range(4):
        pe.process_one()

    ok = (pe.result == [14, 20, 26]) and (pe.finished == 1)
    print_result("result", pe.result, [14, 20, 26], ok)
    return ok


def test_with_accumulation():
    """Test2: data=[0,1,2,3,4], filter=[4,3,2], psum_in=[10,20,30]
    dot: [7,16,25], 累加后: [17,36,55]
    """
    print("\n" + "=" * 50)
    print("TEST 2: MAC + Psum Accumulation")
    pe = PE(3)
    pe.in_data = [0, 1, 2, 3, 4]
    pe.in_filter = [4, 3, 2]
    pe.in_result = [10, 20, 30, 0, 0]
    pe.start = [1]
    pe.new_in_data = [1]

    for i in range(4):
        pe.process_one()

    ok = (pe.result == [17, 36, 55]) and (pe.finished == 1)
    print_result("result", pe.result, [17, 36, 55], ok)
    return ok


def test_timing():
    """Test3: 验证5拍时序: IDLE->MAC(iter0)->MAC(iter1)->MAC(iter2)->ACC->DONE->IDLE"""
    print("\n" + "=" * 50)
    print("TEST 3: Timing Sequence")
    pe = PE(3)
    pe.in_data = [1, 2, 3, 4, 5]
    pe.in_filter = [1, 1, 1]
    pe.in_result = [0, 0, 0, 0, 0]
    pe.start = [1]
    pe.new_in_data = [1]

    # start拍同时完成数据锁存和iter=0的MAC, 因此iter在start拍后变为1
    expected_sequence = [
        (1, 1, 1, 0, [6, 0, 0]),   # start拍: MAC iter=0完成, iter->1, out_start=1
        (1, 2, 0, 0, [6, 9, 0]),   # 第2拍: MAC iter=1, iter->2, out_start=0
        (2, 0, 0, 0, [6, 9, 12]),  # 第3拍: MAC iter=2, state->ACC, iter->0
        (3, 0, 0, 1, [6, 9, 12]),  # 第4拍: ACC->DONE, finished=1
        (0, 0, 0, 0, [6, 9, 12]),  # 第5拍: DONE->IDLE
    ]

    all_ok = True
    for step, (exp_state, exp_iter, exp_out_start, exp_finished, exp_result) in enumerate(expected_sequence):
        pe.process_one()
        actual = (pe.state, pe.iteration, pe.out_start[0], pe.finished, pe.result.copy())
        exp = (exp_state, exp_iter, exp_out_start, exp_finished, exp_result)
        ok = actual == exp
        if not ok:
            print(f"  Step {step}: actual={actual}, expected={exp}")
            all_ok = False

    print(f"  {'PASS' if all_ok else 'FAIL'}")
    return all_ok


def test_data_latching():
    """Test4: new_in_data=0时, filter仍更新(原设计), data保持不变
    start=1, new_in_data=0, in_data=[9,9,9,9,9], in_filter=[2,2,2]
    -> data保持[1,2,3,4,5], filter更新为[2,2,2]
    dot=[12,18,24], 累加[100,100,100] = [112,118,124]
    """
    print("\n" + "=" * 50)
    print("TEST 4: Data Latching (new_in_data gates only data, filter always updates)")
    pe = PE(3)

    # 第一次: 锁存 [1,2,3,4,5] + [1,1,1], result=[6,9,12]
    pe.in_data = [1, 2, 3, 4, 5]
    pe.in_filter = [1, 1, 1]
    pe.in_result = [0, 0, 0, 0, 0]
    pe.start = [1]
    pe.new_in_data = [1]
    for i in range(5):
        pe.process_one()
    ok1 = (pe.result == [6, 9, 12]) and (pe.state == 0)
    print(f"  First op: result={pe.result}, state={pe.state} — {'OK' if ok1 else 'FAIL'}")

    # 第二次: start=1, new_in_data=0 -> data保持旧值, filter更新
    pe.in_data = [9, 9, 9, 9, 9]
    pe.in_filter = [2, 2, 2]
    pe.in_result = [100, 100, 100, 0, 0]
    pe.start = [1]
    pe.new_in_data = [0]
    for i in range(4):
        pe.process_one()
    # data=[1,2,3,4,5], filter=[2,2,2], dot=[12,18,24], result=[112,118,124]
    ok2 = (pe.result == [112, 118, 124])
    print(f"  Second op: result={pe.result}, expected=[112,118,124] — {'OK' if ok2 else 'FAIL'}")

    return ok1 and ok2


if __name__ == "__main__":
    all_ok = True
    all_ok &= test_basic_mac()
    all_ok &= test_with_accumulation()
    all_ok &= test_timing()
    all_ok &= test_data_latching()

    print("\n" + "=" * 50)
    print(f"OVERALL: {'ALL PASSED' if all_ok else 'SOME FAILED'}")
    print("=" * 50)
