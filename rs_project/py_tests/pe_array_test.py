"""
PE Array 3x3 测试 — 验证简化RS数据流
用法: cd H:\cc_project\rs_project && python py_tests/pe_array_test.py
"""
import sys; sys.path.insert(0, 'H:/cc_project/rs_project/py')
from pe_array import PEArray

def set_all_ni_d(arr, val):
    for r in range(3):
        for c in range(3): arr.grid[r][c].new_in_data[0] = val

ok = 0; fail = 0

# Test1: Same data — 3行相同, 垂直累加
# data=[1,2,3,4,5], filter=[1,2,3], 3行→[42,60,78]
dp=[1,2,3,4,5]; fp=[1,2,3]
arr = PEArray(3,dp,fp); set_all_ni_d(arr,1); arr.grid[0][0].start[0]=1
for _ in range(10):
    arr.process()
    if arr.finished:
        if arr.grid[2][0].result==[42,60,78]: ok+=1; print("Test1 SameData: PASS")
        else: fail+=1; print(f"Test1 FAIL: {arr.grid[2][0].result}")
        break

# Test2: RS Dataflow — 3拍不同数据
# row0=[1..5]×[1,2,3], row1=[6..10]×[4,5,6], row2=[11..15]×[7,8,9]
data_rows=[[1,2,3,4,5],[6,7,8,9,10],[11,12,13,14,15]]
filt_rows=[[1,2,3],[4,5,6],[7,8,9]]
dp=[0]*5; fp=[0]*3; arr=PEArray(3,dp,fp)
for step in range(15):
    if step<3:
        dp[:]=data_rows[step]; fp[:]=filt_rows[step]; set_all_ni_d(arr,1)
        if step==0: arr.grid[0][0].start[0]=1
    else: set_all_ni_d(arr,0)
    arr.process()
    if arr.finished:
        # Drain
        for _ in range(10):
            all_idle=all(arr.grid[r][c].state==0 for r in range(3) for c in range(3))
            if all_idle: break; arr.process()
        res=list(arr.output)
        if res==[411,456,501]: ok+=1; print("Test2 RS_Dataflow: PASS")
        else: fail+=1; print(f"Test2 FAIL: {res}")
        break

# Test3: Hardware-accurate timing — 选择性new_in_data
dp=[0]*5; fp=[0]*3; arr=PEArray(3,dp,fp)
for step in range(15):
    dp[:]=data_rows[min(step,2)]; fp[:]=filt_rows[min(step,2)]; set_all_ni_d(arr,0)
    if step==0: arr.grid[0][0].new_in_data[0]=1; arr.grid[0][0].start[0]=1
    elif step==1: arr.grid[0][1].new_in_data[0]=1; arr.grid[1][0].new_in_data[0]=1
    elif step==2: arr.grid[0][2].new_in_data[0]=1; arr.grid[1][1].new_in_data[0]=1; arr.grid[2][0].new_in_data[0]=1
    arr.process()
    if arr.finished:
        for _ in range(10):
            all_idle=all(arr.grid[r][c].state==0 for r in range(3) for c in range(3))
            if all_idle: break; arr.process()
        if arr.grid[2][0].result==[411,456,501]: ok+=1; print("Test3 HW_Timing: PASS")
        else: fail+=1; print(f"Test3 FAIL: {arr.grid[2][0].result}")
        break

print(f"\n=== PE Array Tests: {ok}/3 PASS, {fail}/3 FAIL ===")
