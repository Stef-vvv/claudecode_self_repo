"""
系统测试: 小规模6阵列验证 + 全量运行对比golden
"""
import sys
sys.path.insert(0, 'H:/cc_project/py_project/ed_run')
import numpy as np
from bram import BRAM
from scheduler import Scheduler
from aggregator import Aggregator
from write_to_ram import WriteRam


def test_small_6array():
    """
    小规模6阵列测试: 单输入通道, 单输出通道, 3行ifmap.
    手工验证第一个阵列的输出.
    """
    print("=" * 60)
    print("TEST: Small 6-Array Verification")
    print("=" * 60)

    input_bram = BRAM(16*16*32*8*100)
    filter_bram = BRAM(18432*8)
    output_bram = BRAM(18432*8)

    # ifmap: 3 rows x 16 cols, only 1 input channel
    # Fill with test pattern: row r, col c = r*16 + c + 1
    ifmap_vals = []
    for r in range(3):
        row = [float(r * 16 + c + 1) for c in range(16)]
        ifmap_vals.extend(row)
    # Pad to cover all 32*16 rows (rest zeros)
    ifmap_vals += [0.0] * (32 * 16 * 16 - len(ifmap_vals))

    for r in range(32 * 16):
        start = r * 16
        input_bram.write(r, list(ifmap_vals[start:start+16]), 128)

    # filter: 1 output channel, 32 input channels, 3x3 kernel
    # All ones for channel 0, zeros for others
    filt_vals = []
    for f in range(64):
        for c in range(32):
            for kh in range(3):
                for kw in range(3):
                    if f == 0 and c == 0:
                        filt_vals.append(1.0)  # all-ones filter
                    else:
                        filt_vals.append(0.0)

    for r in range(64 * 32 * 3):
        start = r * 3
        row_data = list(filt_vals[start:start+3]) + [0.0]
        filter_bram.write(r, row_data, 32)

    # Run scheduler with a single output channel (oc=0)
    sched = Scheduler(input_bram, filter_bram)
    agg = Aggregator(output_bram, sched.pe_cluster)
    wr = WriteRam(output_bram, sched.pe_cluster, agg)
    sched.aggregator = agg
    sched.write_ram = wr

    # Manual run: only oc=0, ic=0, 6 tile rows
    # For ic=0, oc=0, all filter values are 1.0
    # ifmap row0 cols 0..4: [1,2,3,4,5], PE result[0] = 1+2+3 = 6
    # Array 0 should produce [6, 9, 12] for row 0
    # After 3-row accumulation: [6+?+? , ...]

    # Quick check: manually drive array 0 for one tile
    arr = sched.pe_cluster[0]
    data_port = sched.data_port1
    filter_port = sched.filter_port

    # Reset
    for r in range(3):
        for c in range(3):
            arr.grid[r][c].new_in_data[0] = 0
            arr.grid[r][c].start[0] = 0

    ifmap_rows = [
        [1.0, 2.0, 3.0, 4.0, 5.0],         # row 0 cols 0-4
        [17.0, 18.0, 19.0, 20.0, 21.0],     # row 1 cols 0-4
        [33.0, 34.0, 35.0, 36.0, 37.0],     # row 2 cols 0-4
    ]
    fil_rows = [[1.0, 1.0, 1.0]] * 3

    for step in range(15):
        if step < 3:
            data_port[:] = ifmap_rows[step]
            filter_port[:] = fil_rows[step]
            for r in range(3):
                for c in range(3):
                    arr.grid[r][c].new_in_data[0] = 1
            if step == 0:
                arr.grid[0][0].start[0] = 1
        else:
            for r in range(3):
                for c in range(3):
                    arr.grid[r][c].new_in_data[0] = 0
        arr.process()
        if arr.finished:
            saved = list(arr.output)
            for _ in range(10):
                all_idle = all(arr.grid[r][c].state == 0 for r in range(3) for c in range(3))
                if all_idle: break
                arr.process()
            break

    # Expected: 3 rows accumulated → [6+42+78, 9+45+81, 12+48+84] = [126, 135, 144]
    # Wait: row0=[1,2,3]·[1,1,1]=6, dot1=[2,3,4]=9, dot2=[3,4,5]=12 → [6,9,12]
    # row1=[17,18,19]·[1,1,1]=54, dot1=[18,19,20]=57, dot2=[19,20,21]=60 → [54,57,60]
    # Actually wait: these are the result of one PE row. The three rows accumulate:
    # PE(0,0)=[6,9,12], PE(1,0)=[54,57,60], PE(2,0)=[102,105,108]
    # PE(2,0) after accumulation: [6+54+102, 9+57+105, 12+60+108] = [162, 171, 180]
    # Hmm, need to recalculate. PE(2,0) internally accumulates from above:
    # PE(0,0): result=[6,9,12]
    # PE(1,0): in_result=PE(0,0).result, then computes own result=[54,57,60], then accumulates: [54+6,57+9,60+12]=[60,66,72]
    # PE(2,0): in_result=PE(1,0).result, computes own result=[102,105,108], accumulates: [102+60,105+66,108+72]=[162,171,180]
    # So array output = [162, 171, 180]

    # Row 0: [1,2,3]·[1,1,1] = 6,9,12
    # Row 1: [17,18,19] -> 54,57,60
    # Row 2: [33,34,35] -> 102,105,108
    # PE(2,0) accumulated result: [6+54+102=162, 9+57+105=171, 12+60+108=180]

    expected = [162.0, 171.0, 180.0]
    ok = saved == expected
    print(f"  Array 0 output: {saved}")
    print(f"  Expected:       {expected}")
    print(f"  {'PASS' if ok else 'FAIL'}")
    return ok


def test_full_run_small():
    """
    全量运行的一小部分: 只跑 ic=0, oc=0..2, 然后与golden对比.
    """
    print("\n" + "=" * 60)
    print("TEST: Full Run Subset (ic=0..31, oc=0..2, all tiles)")
    print("=" * 60)

    # Use the actual data
    ifmap_f = np.array([float(l.strip()) for l in open('conv2.input.real.dat')])
    filt_f = np.array([float(l.strip()) for l in open('conv2.real.dat')])

    input_bram = BRAM(16*16*32*8*100)
    filter_bram = BRAM(18432*8)
    output_bram = BRAM(18432*8)

    for r in range(32*16):
        start = r * 16
        input_bram.write(r, list(ifmap_f[start:start+16]), 128)
    for r in range(64*32*3):
        start = r * 3
        filter_bram.write(r, list(filt_f[start:start+3]) + [0.0], 32)

    sched = Scheduler(input_bram, filter_bram)
    agg = Aggregator(output_bram, sched.pe_cluster)
    wr = WriteRam(output_bram, sched.pe_cluster, agg)
    sched.aggregator = agg
    sched.write_ram = wr

    # Run a subset: limit oc loop
    # We'll modify the scheduler to only run 3 output channels
    num_layers = 32
    num_rows = 20
    num_filters = 3  # Only first 3 output channels

    for input_layer in range(num_layers):
        for skip_row in range(0, num_rows - 4, 3):
            # Reset new_in_data
            for arr in sched.pe_cluster:
                for j in range(3):
                    for i in range(3):
                        arr.grid[j][i].new_in_data[0] = 1
                        if i == 2 and j == 2:
                            arr.grid[j][i].new_in_data[0] = 0
            new = 1

            for out_f in range(num_filters):
                for arr in sched.pe_cluster:
                    arr.grid[0][0].start[0] = 1

                for count, row in enumerate(range(skip_row, skip_row + 5)):
                    if out_f == 0:
                        read_address = input_layer * 16 + row - 1
                        if row == 0 or row >= 17:
                            ifs_row = [0.0] * 18
                        else:
                            ifs_row = [0.0] + input_bram.read(read_address, 128) + [0.0]
                        sched.data_port1[:] = ifs_row[0:5]
                        sched.data_port2[:] = ifs_row[3:8]
                        sched.data_port3[:] = ifs_row[6:11]
                        sched.data_port4[:] = ifs_row[9:14]
                        sched.data_port5[:] = ifs_row[12:17]
                        sched.data_port6[:] = ifs_row[13:18]

                    if count < 3:
                        filter_address = out_f * 32 * 3 + input_layer * 3 + count
                        sched.filter_port[:] = filter_bram.read(filter_address, 32)[:3]

                    if count < 4:
                        sched.process_step()

                    if 1 <= count < 4:
                        out_address = out_f * 16 + row - 1
                        agg.address_queue.append(out_address)

                    if new and count == 0:
                        new = 0
                        for arr in sched.pe_cluster:
                            arr.grid[2][2].new_in_data[0] = 1

                for arr in sched.pe_cluster:
                    arr.grid[0][0].start[0] = 0

    # Drain
    for i in range(100):
        sched.process_step()

    # Compare first 3 output channels against golden
    golden = np.array([float(l.strip()) for l in open('conv2.output.real.dat')])
    our_output = []
    for addr in range(16*16*3):  # First 3 channels × 16×16
        our_output.append(output_bram.mem[addr])

    golden_subset = golden[:16*16*3]
    our_subset = np.array(our_output[:16*16*3])

    diff = np.abs(golden_subset - our_subset)
    exact = np.sum(diff < 1e-10)
    within_1lsb = np.sum(np.abs(np.round(golden_subset*256) - np.round(our_subset*256)) <= 1)

    print(f"  Subset size: {len(golden_subset)}")
    print(f"  Exact matches: {exact}/{len(golden_subset)}")
    print(f"  Within 1 LSB: {within_1lsb}/{len(golden_subset)}")

    if exact < len(golden_subset):
        bad = np.where(diff >= 1e-10)[0]
        print(f"  First 10 diffs:")
        for i in bad[:10]:
            ch = i // 256
            row = (i % 256) // 16
            col = i % 16
            print(f"    ch={ch} r={row} c={col}: our={our_subset[i]:+.6f} golden={golden_subset[i]:+.6f}")

    return exact > len(golden_subset) * 0.95  # 95% exact match


if __name__ == "__main__":
    ok1 = test_small_6array()
    print("\n... Next test requires running full conv subset, this may take a while ...")
    # Only run if first test passes
    if ok1:
        ok2 = test_full_run_small()
        print(f"\n{'='*60}")
        print(f"OVERALL: {'PASSED' if ok1 and ok2 else 'SOME FAILED'}")
        print(f"{'='*60}")
    else:
        print("\nSmall test failed — skipping full test")
