# Python 行为级模型使用说明

## 概述

`py/eyeriss_model.py` 是 Eyeriss v1 加速器的周期精确 Python 行为模型。

**作用**:
1. 为 RTL 仿真提供 golden reference (期望输出)
2. 验证地址生成逻辑 (与C模型和SV RTL使用相同公式)
3. 快速评估不同层配置的计算量和存储需求
4. 毕业设计中的"行为级建模"章节素材

## 与RTL的对应关系

| 模型组件 | 对应RTL | 验证方式 |
|----------|---------|----------|
| `Scheduler.generate_passes()` | scheduler.sv FSM | 循环结构一致 |
| `IndexGenerators.ifmap_addresses()` | ifmap_index_generator.sv | 地址公式一致 |
| `IndexGenerators.filter_addresses()` | filter_index_generator.sv | lock-step计数器一致 |
| `IndexGenerators.psum_addresses()` | psum_index_generator.sv | lock-step计数器一致 |
| `Mapper` (内嵌在IndexGenerators中) | mapper.sv | addr=idx4*d3*d2*d1+... |
| `GLB.write_port_a()` | ifmap_glb.sv Port A | 64-bit→4 bank拆分 |
| `GLB.read_port_b()` | ifmap_glb.sv Port B | 16-bit bank选择 |
| `EyerissModel.compute_golden()` | PE阵列 | Q3.13 MAC |

## 使用方法

### 基本用法
```python
from eyeriss_model import LayerConfig, EyerissModel
import numpy as np

# 1. 定义层配置
cfg = LayerConfig(
    H=8, W=8,       # ifmap 8×8
    R=3, S=3,       # filter 3×3
    E=6, F=6,       # ofmap 6×6 (stride 1, no pad)
    C=1, M=1,       # 1通道输入, 1通道输出
    N=1, U=1,       # batch=1, stride=1
    m=1, n=1, e=6,  # 映射参数
    p=1, q=1, r=1, t=1
)

# 2. 创建模型
model = EyerissModel(cfg)

# 3. 加载测试数据 (必须是非零有效数据!)
ifmap = np.arange(1, 65).reshape(1, 1, 8, 8) * 256  # Q3.13
filter_w = np.array([[[[1,0,0],[0,2,0],[0,0,1]]]]) * 256
bias = np.array([0])

model.load_test_data(ifmap, filter_w, bias)

# 4. 计算golden reference
golden = model.compute_golden()
print(golden)  # shape: (N, M, F, E)

# 5. 查看pass信息
model.print_summary()
```

### 自定义层
```python
# 用户目标层: 16×16×32 → 16×16×64, K=3×3, pad=1
cfg = LayerConfig(
    H=18, W=18,     # 16+2pad
    R=3, S=3, E=16, F=16,
    C=32, M=64, N=1, U=1,
    m=16, n=1, e=8, p=8, q=4, r=2, t=4
)
```

### 生成GLB地址追踪
```python
passes = model.scheduler.generate_passes()
for p in passes:
    addrs = model.idx_gen.ifmap_addresses(p['ifmap_start'], p['channel_start'], ifmap)
    for idx, ch, row, col, addr in addrs:
        glb_val = model.ifmap_glb.read_port_b(addr)
        print(f"GLB[{addr}] = {glb_val}  (ifmap[{idx}][{ch}][{row}][{col}])")
```

## 数据格式

### Q3.13 定点
- 16-bit有符号整数
- 1 bit 符号 + 2 bits 整数 + 13 bits 小数
- 范围: [-4.0, 3.9999]
- 转换: `q_val = int(round(float_val * 8192))`

### GLB数据布局 (64-bit Port A)
```
GLB 64-bit word [15:0]  → bank 0 [sub_addr]
                [31:16] → bank 1 [sub_addr]
                [47:32] → bank 2 [sub_addr]
                [63:48] → bank 3 [sub_addr]
```

### GLB数据布局 (16-bit Port B)
```
GLB 16-bit read: addr[1:0] 选择bank
                 addr>>2   为sub-address
```

## 验证状态
- [x] Golden reference 与独立Python conv2d结果一致
- [x] ifmap地址追踪与C模型一致
- [x] filter地址追踪与C模型一致
- [x] psum地址追踪与C模型一致
- [x] 与RTL编译参数一致
