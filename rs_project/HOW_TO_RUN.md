# 运行指南

## 1. Python行为模型

### 环境: Python 3.x (无需额外安装)

### 1.1 PE单元测试
```bash
cd H:\cc_project\rs_project
python py_tests/pe_test.py
```
期望输出: `PE Tests: 4/4 PASS`

### 1.2 PE Array测试
```bash
cd H:\cc_project\rs_project
python py_tests/pe_array_test.py
```
期望输出: `PE Array Tests: 3/3 PASS`

验证关键点: Test2产生[411,456,501], 这是对3×3卷积的数学正确结果.

### 1.3 顶层集成测试
```bash
cd H:\cc_project\rs_project
python py_tests/top_test.py
```
期望输出: `Top Tests: 3/3 PASS`

包含: 单tile验证, 背靠背两tile连续处理.

### 1.4 完整conv2 (需要时间长)
```bash
cd H:\cc_project\rs_project
python -c "
import sys; sys.path.insert(0,'py')
from top import Top
t=Top(); t.initialize(); t.run()
print('Output saved to ed_run_output.dat')
"
```
对比golden:
```bash
cd H:\cc_project\rs_project
python -c "
import numpy as np
our=np.array([float(l.strip()) for l in open('ed_run_output.dat')])
ref=np.array([float(l.strip()) for l in open('data/conv2.output.real.dat')])
diff=np.abs(our-ref)
print(f'Exact: {np.sum(diff<1e-10)}/16384, Within 1LSB: {np.sum(np.abs(np.round(our*256)-np.round(ref*256))<=1)}/16384')
"
```

## 2. RTL仿真 (Vivado 2020.2)

### 环境: Vivado 2020.2 (xvlog + xelab + xsim)

本机路径: `E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin`

### 2.1 PE仿真
```bash
cd H:\cc_project\rs_project\tb
set VIVADO=E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin
%VIVADO%/xvlog ../rtl/pe.v pe_tb.v
%VIVADO%/xelab -L xil_defaultlib -s pe_sim pe_tb
%VIVADO%/xsim pe_sim -R
```
期望输出: `ALL TESTS PASSED`

### 2.2 PE Array仿真
```bash
cd H:\cc_project\rs_project\tb
%VIVADO%/xvlog ../rtl/pe.v ../rtl/pe_array.v pe_array_tb.v
%VIVADO%/xelab -L xil_defaultlib -s pa_sim pe_array_tb
%VIVADO%/xsim pa_sim -R
```
期望输出: `ALL TESTS PASSED`

### 2.3 单阵列系统仿真
```bash
cd H:\cc_project\rs_project\tb
%VIVADO%/xvlog ../rtl/pe.v ../rtl/pe_array.v ../rtl/scheduler.v ../rtl/aggregator.v ../rtl/rs_top.v rs_top_tb.v
%VIVADO%/xelab -L xil_defaultlib -s sys_sim rs_top_tb
%VIVADO%/xsim sys_sim -R
```
期望输出:
```
Test1: RS Dataflow [411,456,501] — PASS
Test2: All-ones [18,27,36] — PASS
Test3: Accumulation [118,227,336] — PASS
ALL SYSTEM TESTS PASSED
```

### 2.4 6阵列系统仿真
```bash
cd H:\cc_project\rs_project\tb
%VIVADO%/xvlog ../rtl/pe.v ../rtl/pe_array.v ../rtl/scheduler_6array.v ../rtl/aggregator_6array.v ../rtl/rs_top_6array.v rs_top_6array_tb.v
%VIVADO%/xelab -L xil_defaultlib -s top6_sim rs_top_6array_tb
%VIVADO%/xsim top6_sim -R
```
期望输出: `6-ARRAY TEST PASSED`

## 3. 波形查看

在xsim中查看波形 (替代-R用-gui):
```bash
%VIVADO%/xsim top6_sim -gui
```
进入GUI后:
1. 在Objects窗口选择信号
2. 右键 Add to Wave Window
3. 点击 Run All
4. 缩放查看关键时序区间

**关键信号说明 (PE_test)**:
- `start` → 1拍脉冲, 触发PE
- `state` → 0(IDLE)→1(MAC)→2(ACC)→3(DONE)→0
- `out_start` → 2拍高电平 (iter=0,1)
- `finished` → 1拍高电平 (ACC→DONE)
- `result_r[0:2]` → 在MAC状态逐拍更新

**关键信号说明 (PE Array)**:
- `start_global` → 仅T0为1, 后续由out_start传播
- `os_00, os_10, os_20` → 对角线传播路径
- `fin_20` → 最先完成的是列0底部PE
- 验证: T=0时start_global=1, T=~55ns时fin_20=1 → 约6周期完成

## 4. 顶层Python说明

**顶层运行入口**: `py/top.py` — Top类

**激励配置流程**:
1. `Top.initialize()`: 从`data/conv2.input.real.dat`加载IFMAP到input_bram, 从`data/conv2.real.dat`加载FILTER到filter_bram
2. `Top.run()`: 运行Scheduler (遍历ic/tile/oc), 驱动6个PE阵列, Aggregator拼接, WriteRam写回
3. 输出写入`ed_run_output.dat` (16,384个浮点值)

**整体数据流**:
```
conv2.input.real.dat → input_bram ─┐
                                     ├→ Scheduler → 6×PE_Array → Aggregator → WriteRam → ed_run_output.dat
conv2.real.dat → filter_bram ──────┘
```
