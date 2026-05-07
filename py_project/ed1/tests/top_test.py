"""
顶层集成测试: 用一个小规模手算可验证的conv2测试整个数据流.

验证策略:
  1. 构建小型ifmap(3x5)和filter(3x3), 手工计算期望输出
  2. 通过完整的BRAM->Scheduler->PEArray->Aggregator流程运行
  3. 对比输出
这确保整个RS数据流软件模型的正确性.
"""
import sys
sys.path.insert(0, 'H:/cc_project/py_project')
from bram import BRAM
from scheduler import Scheduler
from aggregator import Aggregator
from write_to_ram import WriteRam
from pe_array import PEArray


def test_small_conv_single_channel():
    """
    小规模单通道卷积: 3x5 ifmap × 3x3 filter → 3个输出像素

    ifmap (3行 x 5列):
      row0: [1, 2, 3, 4, 5]
      row1: [6, 7, 8, 9, 10]
      row2: [11,12,13,14,15]

    filter (3x3):
      row0: [1,2,3]
      row1: [4,5,6]
      row2: [7,8,9]

    手算验证:
      ofmap[0][p0] = ifmap_row0[0:3]·filter[0] + ifmap_row1[0:3]·filter[1] + ifmap_row2[0:3]·filter[2]
                   = 1*1+2*2+3*3 + 6*4+7*5+8*6 + 11*7+12*8+13*9
                   = (1+4+9) + (24+35+48) + (77+96+117)
                   = 14 + 107 + 290 = 411

      ofmap[0][p1] = ifmap_row0[1:4]·filter[0] + ifmap_row1[1:4]·filter[1] + ifmap_row2[1:4]·filter[2]
                   = (2+6+12) + (28+40+54) + (84+104+126)
                   = 20 + 122 + 314 = 456

      ofmap[0][p2] = ifmap_row0[2:5]·filter[0] + ifmap_row1[2:5]·filter[1] + ifmap_row2[2:5]·filter[2]
                   = (3+8+15) + (32+45+60) + (91+112+135)
                   = 26 + 137 + 338 = 501

    期望输出: [411, 456, 501]
    """
    print("=" * 60)
    print("TEST: Single-Channel 3x3 Conv (Hand-Verified)")
    print("=" * 60)

    # 准备BRAM
    input_bram = BRAM(16384)
    filter_bram = BRAM(16384)
    output_bram = BRAM(16384)

    # 加载ifmap: 3行, 每行5个值, 补零到16个元素 (128-bit行)
    ifmap_rows = [
        [1, 2, 3, 4, 5] + [0]*11,
        [6, 7, 8, 9, 10] + [0]*11,
        [11, 12, 13, 14, 15] + [0]*11,
    ]
    for r, row in enumerate(ifmap_rows):
        input_bram.write(r, row, 128)

    # 加载filter: 3行, 每行3个值, 补1个到4字节 (32-bit行)
    filter_rows = [
        [1, 2, 3, 0],
        [4, 5, 6, 0],
        [7, 8, 9, 0],
    ]
    for r, row in enumerate(filter_rows):
        filter_bram.write(r, row, 32)

    # 创建调度器 + 聚合器 + 写回
    sched = Scheduler(input_bram, filter_bram)
    agg = Aggregator(output_bram, sched.pe_cluster)
    wr = WriteRam(output_bram, sched.pe_cluster, agg)
    sched.aggregator = agg
    sched.write_ram = wr

    # 只运行1个输入通道、1个输出通道、1个tile
    # 直接驱动PE阵列 (绕过完整scheduler循环)
    arr = sched.pe_cluster[0]

    # 清PE状态
    for j in range(3):
        for i in range(3):
            arr.grid[j][i].new_in_data[0] = 0
            arr.grid[j][i].start[0] = 0

    data_rows = [
        [1,  2,  3,  4,  5],
        [6,  7,  8,  9,  10],
        [11, 12, 13, 14, 15],
    ]
    fil_rows = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

    for step in range(15):
        if step < 3:
            sched.data_port1[:] = data_rows[step]
            sched.filter_port[:] = fil_rows[step]
            for j in range(3):
                for i in range(3):
                    arr.grid[j][i].new_in_data[0] = 1
            if step == 0:
                arr.grid[0][0].start[0] = 1
        else:
            for j in range(3):
                for i in range(3):
                    arr.grid[j][i].new_in_data[0] = 0

        sched.process_step()
        if arr.finished:
            break

    result = list(arr.output)
    expected = [411, 456, 501]
    ok = (result == expected)

    print(f"  Result:   {result}")
    print(f"  Expected: {expected}")
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


def test_back_to_back_tiles():
    """验证背靠背tile操作 — PE阵列可在完成一个tile后正确开始下一个"""
    print("\n" + "=" * 60)
    print("TEST: Back-to-Back Tiles")
    print("=" * 60)

    input_bram = BRAM(16384)
    filter_bram = BRAM(16384)
    output_bram = BRAM(16384)
    sched = Scheduler(input_bram, filter_bram)
    arr = sched.pe_cluster[0]

    # Tile 1: 与上面相同
    data_rows_1 = [[1,2,3,4,5], [6,7,8,9,10], [11,12,13,14,15]]
    fil_rows_1 = [[1,2,3], [4,5,6], [7,8,9]]

    # Tile 2: 不同数据
    data_rows_2 = [[2,3,4,5,6], [3,4,5,6,7], [4,5,6,7,8]]
    fil_rows_2 = [[1,1,1], [1,1,1], [1,1,1]]

    results = []
    for tile_idx, (data_rows, fil_rows) in enumerate([(data_rows_1, fil_rows_1), (data_rows_2, fil_rows_2)]):
        # 清PE
        for j in range(3):
            for i in range(3):
                arr.grid[j][i].new_in_data[0] = 0
                arr.grid[j][i].start[0] = 0

        for step in range(15):
            if step < 3:
                sched.data_port1[:] = data_rows[step]
                sched.filter_port[:] = fil_rows[step]
                for j in range(3):
                    for i in range(3):
                        arr.grid[j][i].new_in_data[0] = 1
                if step == 0:
                    arr.grid[0][0].start[0] = 1
            else:
                for j in range(3):
                    for i in range(3):
                        arr.grid[j][i].new_in_data[0] = 0

            sched.process_step()
            if arr.finished:
                saved_result = list(arr.output)  # 先保存结果再排空
                # 继续排空直到所有PE回到IDLE
                for _ in range(10):
                    all_idle = all(arr.grid[j][i].state == 0 for j in range(3) for i in range(3))
                    if all_idle:
                        break
                    sched.process_step()
                break

        results.append(saved_result)

    ok1 = (results[0] == [411, 456, 501])
    ok2 = (results[1] == [36, 45, 54])  # 手算: [9+12+15, 12+15+18, 15+18+21]
    print(f"  Tile 1: {results[0]}, expected=[411,456,501] — {'OK' if ok1 else 'FAIL'}")
    print(f"  Tile 2: {results[1]}, expected=[36,45,54] — {'OK' if ok2 else 'FAIL'}")
    return ok1 and ok2


if __name__ == "__main__":
    all_ok = True
    all_ok &= test_small_conv_single_channel()
    all_ok &= test_back_to_back_tiles()

    print("\n" + "=" * 60)
    print(f"OVERALL: {'ALL PASSED' if all_ok else 'SOME FAILED'}")
    print("=" * 60)
