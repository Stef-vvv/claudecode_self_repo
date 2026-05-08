# COE文件生成与Vivado BRAM配置

## COE文件格式

Xilinx COE (Coefficient)文件用于初始化Block Memory Generator IP的初始内容。

### IFMAP BRAM COE

生成脚本:
```python
import numpy as np
data = np.array([float(l.strip()) for l in open('data/conv2.input.real.dat')])
q8 = np.clip(np.round(data * 256), -128, 127).astype(np.int8)

with open('ifmap.coe', 'w') as f:
    f.write('memory_initialization_radix=2;\n')
    f.write('memory_initialization_vector=\n')
    for row in range(32 * 16):  # 512行
        start = row * 16
        # 16个Q8值拼接为128-bit二进制
        bits = ''
        for col in range(16):
            val = q8[start + col] if start + col < len(q8) else 0
            # 转为8-bit二进制字符串
            bits = format(val & 0xFF, '08b') + bits
        f.write(bits + ',\n')
```

### FILTER BRAM COE

生成脚本:
```python
import numpy as np
data = np.array([float(l.strip()) for l in open('data/conv2.real.dat')])
q8 = np.clip(np.round(data * 256), -128, 127).astype(np.int8)

with open('filter.coe', 'w') as f:
    f.write('memory_initialization_radix=2;\n')
    f.write('memory_initialization_vector=\n')
    for row in range(64 * 32 * 3):  # 6144行
        start = row * 3
        bits = ''
        for col in range(3):
            val = q8[start + col] if start + col < len(q8) else 0
            bits = format(val & 0xFF, '08b') + bits
        bits = '00000000' + bits  # 4th byte = padding (0)
        f.write(bits + ',\n')
```

或在命令行中运行 (生成两个COE文件):
```bash
cd H:\cc_project\rs_project
python -c "
import numpy as np

# IFMAP COE
data = np.array([float(l.strip()) for l in open('data/conv2.input.real.dat')])
q8 = np.clip(np.round(data * 256), -128, 127).astype(np.int8)
with open('coe/ifmap.coe', 'w') as f:
    f.write('memory_initialization_radix=2;\nmemory_initialization_vector=\n')
    for row in range(32 * 16):
        start = row * 16
        bits = ''
        for col in range(16):
            v = q8[start + col] if start + col < len(q8) else 0
            bits = format(v & 0xFF, '08b') + bits
        f.write(bits + ('' if row >= 32*16-1 else ',\n'))
print('coe/ifmap.coe generated')

# FILTER COE
data = np.array([float(l.strip()) for l in open('data/conv2.real.dat')])
q8 = np.clip(np.round(data * 256), -128, 127).astype(np.int8)
with open('coe/filter.coe', 'w') as f:
    f.write('memory_initialization_radix=2;\nmemory_initialization_vector=\n')
    for row in range(64 * 32 * 3):
        start = row * 3
        bits = ''
        for col in range(3):
            v = q8[start + col] if start + col < len(q8) else 0
            bits = format(v & 0xFF, '08b') + bits
        bits = '00000000' + bits
        f.write(bits + ('' if row >= 64*32*3-1 else ',\n'))
print('coe/filter.coe generated')
"
```

## Vivado Block Memory Generator IP 配置

### IFMAP BRAM

| 参数 | 值 |
|------|-----|
| Memory Type | Single Port ROM |
| Port A Width | 128 |
| Port A Depth | 512 (32ch × 16rows) |
| Enable Port Type | Always Enabled |
| Memory Initialization | coe/ifmap.coe |

### FILTER BRAM

| 参数 | 值 |
|------|-----|
| Memory Type | Single Port ROM |
| Port A Width | 32 |
| Port A Depth | 6144 (64oc × 32ic × 3rows) |
| Enable Port Type | Always Enabled |
| Memory Initialization | coe/filter.coe |

### OFMAP BRAM (输出)

| 参数 | 值 |
|------|-----|
| Memory Type | True Dual Port RAM |
| Port A Width | 128 |
| Port A Depth | 1024 (64oc × 16rows) |
| Enable Port Type | Always Enabled |
| Write Enable | Byte Write Enable (或全字写使能) |

## 在Vivado项目中使用

1. 创建Vivado项目, 添加所有rtl/*.v文件
2. 用Block Memory Generator创建3个BRAM IP
3. 分别加载对应的COE文件
4. 例化BRAM IP并连接到rs_top_6array模块
5. 编写顶层wrapper, 实现BRAM地址生成和读时序
6. 运行行为仿真/综合/实现

## 数据文件的COE对应关系

| .real.dat文件 | COE文件 | BRAM宽度 | 深度 | 每行数据 |
|--------------|---------|----------|------|----------|
| conv2.input.real.dat (8192值) | ifmap.coe | 128-bit | 512 | 16个Q8值 |
| conv2.real.dat (18432值) | filter.coe | 32-bit | 6144 | 3个Q8值+1字节填充 |
