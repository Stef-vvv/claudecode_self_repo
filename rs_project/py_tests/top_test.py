"""顶层集成测试: PE阵列单tile验证"""
import sys; sys.path.insert(0, 'H:/cc_project/rs_project/py')
from pe_array import PEArray
ok=0; fail=0

def run_one(rows, filts, expected, name):
    global ok, fail
    dp=[0]*5; fp=[0]*3; arr=PEArray(3,dp,fp)
    for r in range(3):
        for c in range(3): arr.grid[r][c].new_in_data[0]=0; arr.grid[r][c].start[0]=0
    for step in range(15):
        if step<3:
            dp[:]=rows[step]; fp[:]=filts[step]
            for r in range(3):
                for c in range(3): arr.grid[r][c].new_in_data[0]=1
            if step==0: arr.grid[0][0].start[0]=1
        else:
            for r in range(3):
                for c in range(3): arr.grid[r][c].new_in_data[0]=0
        arr.process()
        if arr.finished:
            saved=list(arr.output)
            for _ in range(15):
                all_idle=all(arr.grid[r][c].state==0 for r in range(3) for c in range(3))
                if all_idle: break; arr.process()
            if saved==expected: ok+=1; print(f"{name}: PASS")
            else: fail+=1; print(f"{name} FAIL: got {saved} expected {expected}")
            return
    fail+=1; print(f"{name} FAIL: never finished")

run_one([[1,2,3,4,5],[6,7,8,9,10],[11,12,13,14,15]], [[1,2,3],[4,5,6],[7,8,9]],
        [411,456,501], "Test1 RS_Dataflow")
run_one([[1,2,3,4,5],[1,2,3,4,5],[1,2,3,4,5]], [[1,1,1],[1,1,1],[1,1,1]],
        [18,27,36], "Test2 SameData")
run_one([[1,2,3,4,5],[1,2,3,4,5],[1,2,3,4,5]], [[1,2,3],[1,2,3],[1,2,3]],
        [42,60,78], "Test3 FilterReuse")

print(f"\n=== Top Tests: {ok}/3 PASS, {fail}/3 FAIL ===")
