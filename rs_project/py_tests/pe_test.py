"""
PE 单元测试 — 手工可验证的4项测试
用法: cd H:\cc_project\rs_project && python py_tests/pe_test.py
"""
import sys; sys.path.insert(0, 'H:/cc_project/rs_project/py')
from pe import PE

ok = 0; fail = 0

# Test1: Basic MAC — data=[1,2,3,4,5], filter=[1,2,3], psum=[0,0,0]
# dot0=1*1+2*2+3*3=14, dot1=2*1+3*2+4*3=20, dot2=3*1+4*2+5*3=26
pe = PE(3); pe.in_data=[1,2,3,4,5]; pe.in_filter=[1,2,3]; pe.in_result=[0,0,0,0,0]
pe.start=[1]; pe.new_in_data=[1]
for i in range(4): pe.process_one()
if pe.result==[14,20,26] and pe.finished==1: ok+=1; print("Test1 Basic MAC: PASS")
else: fail+=1; print(f"Test1 FAIL: {pe.result} expected [14,20,26]")

# Test2: MAC+Accumulation — psum=[10,20,30]
pe = PE(3); pe.in_data=[0,1,2,3,4]; pe.in_filter=[4,3,2]; pe.in_result=[10,20,30,0,0]
pe.start=[1]; pe.new_in_data=[1]
for i in range(4): pe.process_one()
if pe.result==[17,36,55] and pe.finished==1: ok+=1; print("Test2 MAC+ACC: PASS")
else: fail+=1; print(f"Test2 FAIL: {pe.result} expected [17,36,55]")

# Test3: 5-cycle FSM — 检查第4拍finished=1, 第5拍回到IDLE
pe = PE(3); pe.in_data=[1,2,3,4,5]; pe.in_filter=[1,1,1]; pe.in_result=[0,0,0,0,0]
pe.start=[1]; pe.new_in_data=[1]
for i in range(3): pe.process_one()  # 前3拍: MAC×3
t_ok = (pe.state==2 and pe.finished==0)  # 第3拍后: ACC, not yet finished
pe.process_one()  # 第4拍: ACC→DONE
t_ok = t_ok and (pe.state==3 and pe.finished==1)  # finished=1 ✓
pe.process_one()  # 第5拍: DONE→IDLE
t_ok = t_ok and (pe.state==0 and pe.finished==0)  # back to IDLE
if t_ok: ok+=1; print("Test3 Timing: PASS")
else: fail+=1; print("Test3 FAIL")

# Test4: new_in_data=0 -> data保持旧值, filter更新
pe = PE(3); pe.in_data=[1,2,3,4,5]; pe.in_filter=[1,1,1]; pe.in_result=[0,0,0,0,0]
pe.start=[1]; pe.new_in_data=[1]
for i in range(5): pe.process_one()  # 回到IDLE
pe.in_data=[9,9,9,9,9]; pe.in_filter=[2,2,2]; pe.in_result=[100,100,100,0,0]
pe.start=[1]; pe.new_in_data=[0]  # 不锁存新data
for i in range(4): pe.process_one()
# data保持[1,2,3,4,5], filter更新为[2,2,2], dot=[12,18,24], result=[112,118,124]
if pe.result==[112,118,124]: ok+=1; print("Test4 Latching: PASS")
else: fail+=1; print(f"Test4 FAIL: {pe.result} expected [112,118,124]")

print(f"\n=== PE Tests: {ok}/4 PASS, {fail}/4 FAIL ===")
