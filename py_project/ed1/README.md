# 简化RS数据流加速器 — Python行为级模型

## 项目结构

```
py_project/
├── pe.py            # PE (处理单元) 行为模型
├── pe_array.py      # PE Array (3x3脉动阵列) 行为模型
├── scheduler.py     # 调度器 (数据分发+时序控制)
├── bram.py          # 块存储器模型
├── aggregator.py    # 输出聚合器
├── write_to_ram.py  # 写回BRAM
├── conv2.input.real.dat   # 输入特征图数据 (16x16x32)
├── conv2.real.dat         # 滤波器数据 (64x32x3x3)
├── conv2.output.real.dat  # 参考输出 (64x16x16)
└── tests/
    ├── pe_test.py          # PE单元测试 (4项)
    ├── pe_array_test.py    # PE Array单元测试 (3项)
    ├── top_test.py         # 顶层集成测试 (2项)
    └── verify_reference.py # 参考输出验证脚本 (需要numpy)
```

## 架构概述

本工程实现了一个基于 **Eyeriss 行平稳(Row-Stationary)数据流** 的简化卷积加速器行为级模型。

### 数据流简化

标准RS数据流中，数据沿对角线在PE之间共享。本工程的简化方案是:

- **数据广播**: 同一时钟周期所有PE看到相同的全局数据总线
- **Start对角线传播**: PE(0,0)收到start后, out_start向右/下传播, 形成对角线启动波
- **分时复用**: Scheduler在不同时钟周期切换数据总线内容, PE在收到start时锁存当前总线数据
- **等效3x1列**: 由于数据广播, 只有第0列PE产生有效结果; 第1、2列PE执行冗余计算(模拟RS的2D运动)

### PE结构

- 5输入滑动窗口, 3滤波器权重
- 5周期状态机: IDLE → MAC(3拍) → ACC(1拍) → DONE(1拍)
- start拍的同一周期完成数据锁存和第一个点积计算

### PE Array结构

- 3x3 PE阵列
- 数据: 全局广播
- 滤波器: 列0→列1→列2 向右传播
- 部分和: 行0→行1→行2 向下传播 (仅在上方PE完成时)
- 启动: 对角线传播 (上方ou_start 或 左方out_start)
- 输出: 取最底部行第一个完成的PE结果

## 运行测试

```bash
cd H:\cc_project\py_project\tests

# PE单元测试
python pe_test.py

# PE Array测试
python pe_array_test.py

# 顶层集成测试 (手工验证小规模卷积)
python top_test.py
```

## 测试验证方法

### 1. PE单元测试 (pe_test.py)

| 测试 | 输入 | 期望输出 | 验证内容 |
|------|------|----------|----------|
| Basic MAC | data=[1..5], filter=[1,2,3] | [14,20,26] | 基本滑动窗口点积 |
| MAC+ACC | psum=[10,20,30] | [17,36,55] | 部分和累加 |
| Timing | data=[1..5], filter=[1,1,1] | 5周期FSM序列 | 状态机时序 |
| Data Latching | new_in_data=0 | data保持旧值 | 数据锁存控制 |

### 2. PE Array测试 (pe_array_test.py)

| 测试 | 验证内容 | 期望PE(2,0)结果 |
|------|----------|-----------------|
| Same Data | 3行相同数据垂直累加 | [42,60,78] |
| RS Dataflow | 3拍不同数据模拟时间分片 | [411,456,501] |
| Hardware Timing | 选择性new_in_data | [411,456,501] |

### 3. 顶层集成测试 (top_test.py)

手工计算验证3x3卷积: 5x3 ifmap × 3x3 filter = 3x1 ofmap
- ifmap: [1..15] (3行x5列)
- filter: [[1,2,3],[4,5,6],[7,8,9]]
- 期望输出: [411,456,501]

计算的验证公式:
```
ofmap[p] = Σ(kh) Σ(kw) ifmap[kh][p+kw] × filter[kh][kw]
```

## 已知问题

1. **原工程输出与参考输出有差异**: 原工程top.py的完整conv2输出与参考文件conv2.output.real.dat存在8922处差异(共16384值)。这需要在完整Scheduler层面进一步调试。

2. **全量conv2验证**: 当前仅手工验证了小规模单通道卷积。完整32通道×64滤波器的验证需要优化Python性能或使用numpy。

3. **ReLU未实现**: 按原工程设计, ReLU在当前版本未启用。

## 后续RTL开发路线

1. ✅ Python行为模型验证 (pe, pe_array)
2. 待完成: wavedrom时序图 (每模块)
3. 待完成: 可综合Verilog (PE, PE_Array, Scheduler)
4. 待完成: testbench仿真验证
