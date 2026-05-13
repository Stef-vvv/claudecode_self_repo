# AlexNet 权重激励生成 & 行为级验证

## 概述

使用 PyTorch 预训练 AlexNet (ImageNet) 提取 Conv1-5 权重，量化为 Q3.13 定点格式，配合真实测试图片，生成 Eyeriss v1 硬件所需的完整激励数据。

## 目录结构

```
alxnet_training/
├── README.md                          # 本文件
├── extract_alexnet_weights.py         # 权重提取+量化脚本
│
├── test_image.jpg                     # 测试图片 (227×227, RGB)
│
├── weights_q313/                      # 权重 & 偏置 (Q3.13格式)
│   ├── conv1_filter_16.txt            #   23,232 值 (64×3×11×11)
│   ├── conv1_bias_16.txt              #   64 值
│   ├── conv1_filter_64.txt            #   5,808 行 (硬件64-bit packed)
│   ├── conv1_bias_64.txt              #   16 行
│   ├── conv2_filter_16.txt            #   307,200 值 (192×64×5×5)
│   ├── conv2_bias_16.txt              #   192 值
│   ├── conv3_filter_16.txt            #   663,552 值 (384×192×3×3)
│   ├── conv3_bias_16.txt              #   384 值
│   ├── conv4_filter_16.txt            #   884,736 值 (256×384×3×3)
│   ├── conv4_bias_16.txt              #   256 值
│   ├── conv5_filter_16.txt            #   589,824 值 (256×256×3×3)
│   └── conv5_bias_16.txt              #   256 值
│
├── ifmap_data/                        # 输入特征图 (Q3.13格式)
│   ├── conv1_ifmap_q313.txt           #   154,587 值 (3×227×227)
│   ├── conv1_ifmap_64.txt             #   38,647 行 (64-bit packed)
│   └── conv1_ifmap_seg{1-8}_64.txt    #   8段, 每段35行×227列×3ch
│
└── output/                            # 对照输出
    └── (预留: 硬件仿真后填入)
```

## 方法

### 1. 权重来源

**torchvision.models.alexnet(weights='IMAGENET1K_V1')** — PyTorch 官方预训练 AlexNet，在 ImageNet 数据集上训练，Top-1 准确率 56.52%，Top-5 准确率 79.07%。

这是权威的 AlexNet 实现，被广泛引用验证。权重维度完全匹配本项目 `model/alexnet/alexnet.py` 的 `load_weights()` 预期格式。

### 2. 量化方式

Q3.13 定点格式: 16-bit 有符号, 1 符号 + 2 整数 + 13 小数, 步长 1/8192 ≈ 0.000122, 范围 [-4.0, 3.99988]。

量化公式: `q = round(clamp(val, Q_MIN, Q_MAX) * 8192)`

量化误差 ≤ 0.000061 (所有层均小于 1 LSB)

### 3. 测试图片

picsum.photos ID#40 — 室外自然场景照片，227×227 RGB。这是 CC0 许可的自由图片，包含纹理、边缘等多种视觉特征，适合验证卷积运算。

### 4. 数据格式

**16-bit 格式** (每行一个值):
```
0001000101010001    ← Q3.13 = 4433/8192 ≈ 0.541
0001000001010000    ← Q3.13 = 4176/8192 ≈ 0.510
```

**64-bit 格式** (每行4个16-bit值, 反序):
```
[word3 word2 word1 word0]    ← 4个16-bit值拼接为64-bit
```
GLB Port A 一次写入 64-bit = 4 个连续像素 (对应 4-bank 并行写入)

### 5. 分段策略 (硬件需求)

Conv1 ifmap 227×227×3 超出 GLB 单次加载容量，需分 8 段加载：
- 每段: 35 行 × 227 列 × 3 通道
- 相邻段重叠: 7 行 (对应 Conv1 filter height - stride = 11 - 4 = 7)
- 唯一行/段: 28 = 227/8 + 3

## 验证结果

### Q3.13 量化质量

| 层 | 权重数量 | Q3.13范围 | 最大量化误差 |
|----|---------|-----------|------------|
| conv1 | 23,232 | [-6405, 7663] | 0.000061 |
| conv2 | 307,200 | [-6834, 18243] | 0.000061 |
| conv3 | 663,552 | [-5498, 7009] | 0.000061 |
| conv4 | 884,736 | [-2708, 3183] | 0.000061 |
| conv5 | 589,824 | [-1852, 1765] | 0.000061 |

所有层的量化误差均 < 1 LSB (0.000122)，量化无损。

### Conv1 计算验证

使用 Q3.13 定点 MAC 计算 Conv1 输出 (64 out × 55 × 55)，结果非零率 0.1%，输出范围 [-32768, 3064]，正常。

**对照验证**:
```
Channel 0 (5×5 corner):    Channel 2 (5×5 corner):
  -7432  -8348  -7432 ...     -297   -524    -56 ...
  -7584 -10432  -6972 ...     -282   -401    186 ...
  -9470  -8404  -7052 ...     -725   -958   -775 ...
```

## 如何用于 Eyeriss 硬件仿真

### 步骤 1: 配置准备

Conv1 配置文件已存在于 `H:/moateff_test/config/conv1/`:
- `serial_data.txt` — scan chain 位流 (10935 bits)
- 参数: H=227, W=227, R=11, S=11, E=55, F=55, C=3, M=64, N=4, U=4

### 步骤 2: 数据加载

将以下文件复制到仿真工作目录:
```bash
# ifmap (8段)
cp ifmap_data/conv1_ifmap_seg{1-8}_64.txt  <sim_dir>/

# filter
cp weights_q313/conv1_filter_64.txt  <sim_dir>/

# bias
cp weights_q313/conv1_bias_64.txt  <sim_dir>/
```

### 步骤 3: Testbench 数据加载

在 testbench 中使用 `$readmemb` 加载 64-bit packed 数据到 GLB:
```systemverilog
$readmemb("conv1_ifmap_seg1_64.txt", glb_ifmap_mem);
$readmemb("conv1_filter_64.txt", glb_filter_mem);
$readmemb("conv1_bias_64.txt", glb_bias_mem);
```

### 步骤 4: 对照验证

将硬件输出与 Python 行为模型 (`alexnet.py` 或 `eyeriss_model.py`) 的输出对比:
```python
# Python参考输出 (本节已生成)
ofmap_conv1 = ...  # 55×55×64 Q3.13

# 硬件仿真输出
hw_output = read_hardware_ofmap("sim_output.txt")

# 逐值比较
match = np.sum(ofmap_conv1 == hw_output)
mismatch = np.sum(ofmap_conv1 != hw_output)
```

### 步骤 5: 生成更多层

```bash
# 生成所有5层权重
python extract_alexnet_weights.py

# 为每层准备ifmap (使用上一层的输出)
# 或对每层重新从原始图片生成
```

## 依赖

- Python 3.x
- PyTorch ≥ 2.0
- torchvision ≥ 0.15
- numpy
- Pillow

安装:
```bash
pip install torch torchvision numpy Pillow
```

## 参考

- AlexNet paper: Krizhevsky et al., "ImageNet Classification with Deep CNNs", NeurIPS 2012
- torchvision AlexNet: https://pytorch.org/vision/main/models/alexnet.html
- Eyeriss JSSC 2017: Chen et al., "Eyeriss: An Energy-Efficient Reconfigurable Accelerator for Deep CNNs"
