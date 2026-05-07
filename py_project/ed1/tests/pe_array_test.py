"""
PE Array 单元测试: 3x3阵列, 验证简化RS数据流的正确性.

测试1: 相同数据行 -> 垂直列累加 (最简单验证)
测试2: 不同数据/滤波器每拍 -> RS时间分片仿真 (核心RS验证)
测试3: 选择性new_in_data -> 硬件精确时序仿真
测试4: 输出时序验证
"""
import sys
sys.path.insert(0, 'H:/cc_project/py_project')
from pe_array import PEArray


def set_all_new_in_data(array, val):
    for r in range(array.n):
        for c in range(array.n):
            array.grid[r][c].new_in_data[0] = val


def print_pe_array_details(array, step):
    """全状态打印 (与原工程ed2风格一致)"""
    print(f"\n{'='*60}")
    print(f" State after Step {step}")
    print(f"{'='*60}")

    for label, attr in [("in_data", "in_data"), ("in_filter", "in_filter"),
                         ("start", "start"), ("new_in_data", "new_in_data"),
                         ("data (reg)", "data"), ("filter (reg)", "filter"),
                         ("result", "result"), ("finished", "finished"),
                         ("state", "state")]:
        print(f"\n--- {label} ---")
        for r in range(array.n):
            row = []
            for c in range(array.n):
                val = getattr(array.grid[r][c], attr)
                row.append(str(val))
            print(" | ".join(row))
        print("-" * 50)

    print(f"\nArray finished: {array.finished}, output: {array.output}")
    print("=" * 60)


def test_same_data_accumulation():
    """Test1: 所有行相同数据, 验证3行垂直累加.
    data=[1,2,3,4,5], filter=[1,2,3] -> 每行PE产出[14,20,26]
    累加3行 -> [42,60,78]
    """
    print("=" * 60)
    print("TEST 1: Same Data — Vertical Accumulation")
    print("=" * 60)

    data_port = [1, 2, 3, 4, 5]
    filter_port = [1, 2, 3]
    array = PEArray(3, data_port, filter_port)

    set_all_new_in_data(array, 1)
    array.grid[0][0].start[0] = 1

    for step in range(10):
        array.process()
        if array.finished:
            print(f"  Finished at step {step+1}")
            break

    expected = [42, 60, 78]
    ok = (array.grid[2][0].result == expected)
    print(f"  PE(2,0).result = {array.grid[2][0].result}")
    print(f"  Expected        = {expected}")
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


def test_different_data_per_cycle():
    """Test2: 三拍不同数据 (模拟Scheduler的RS分时数据广播).
    T0: data_row0 + filter_row0 -> PE(0,0)锁存
    T1: data_row1 + filter_row1 -> PE(1,0), PE(0,1)锁存
    T2: data_row2 + filter_row2 -> PE(2,0), PE(1,1), PE(0,2)锁存
    T3..6: 排空流水线, PE(2,0)完成 -> [411,456,501]
    """
    print("\n" + "=" * 60)
    print("TEST 2: RS Dataflow — Time-Multiplexed Data Broadcast")
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
                array.grid[0][0].start[0] = 1
        else:
            set_all_new_in_data(array, 0)

        array.process()
        if array.finished:
            print(f"  Finished at step {step+1}")
            break

    expected = [411, 456, 501]
    ok = (array.grid[2][0].result == expected)
    print(f"  PE(2,0).result = {array.grid[2][0].result}")
    print(f"  Expected        = {expected}")
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


def test_hardware_accurate_timing():
    """Test3: 硬件精确时序 - 只有start传播路径上的PE获得new_in_data.
    结果应与Test2相同 ([411,456,501]), 但new_in_data更精确.
    """
    print("\n" + "=" * 60)
    print("TEST 3: Hardware-Accurate Timing (Selective new_in_data)")
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
        data_port[:] = data_rows[min(step, 2)]
        filter_port[:] = filter_rows[min(step, 2)]

        # 清除所有new_in_data
        set_all_new_in_data(array, 0)

        if step == 0:
            array.grid[0][0].new_in_data[0] = 1
            array.grid[0][0].start[0] = 1
        elif step == 1:
            array.grid[0][1].new_in_data[0] = 1
            array.grid[1][0].new_in_data[0] = 1
        elif step == 2:
            array.grid[0][2].new_in_data[0] = 1
            array.grid[1][1].new_in_data[0] = 1
            array.grid[2][0].new_in_data[0] = 1

        array.process()
        if array.finished:
            print(f"  Finished at step {step+1}")
            break

    expected = [411, 456, 501]
    ok = (array.grid[2][0].result == expected)
    print(f"  PE(2,0).result = {array.grid[2][0].result}")
    print(f"  Expected        = {expected}")
    print(f"  Other columns: PE(2,1)={array.grid[2][1].result}, PE(2,2)={array.grid[2][2].result}")
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


if __name__ == "__main__":
    all_ok = True
    all_ok &= test_same_data_accumulation()
    all_ok &= test_different_data_per_cycle()
    all_ok &= test_hardware_accurate_timing()

    print("\n" + "=" * 60)
    print(f"OVERALL: {'ALL PASSED' if all_ok else 'SOME FAILED'}")
    print("=" * 60)
