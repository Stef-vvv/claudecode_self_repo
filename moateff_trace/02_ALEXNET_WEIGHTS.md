# 任务2: AlexNet权重激励准备方案

## 搜索结论

网上不存在现成的 `conv{1-5}_filter_16.txt` / `conv{1-5}_bias_16.txt` 文件。这些文件名是该Eyeriss项目特有的命名约定。

## 现有条件

### 已验证可用的Python脚本 (model/目录)
- `from_resize_to_pooling_colored.py` — 完整流水线: resize→conv→relu→pool (colored viz)
- `from_resize_to_pooling_gray.py` — 同上 (灰度版本)
- `alexnet/alexnet.py` — 完整AlexNet前向推理 (load_weights读取权重txt)
- `alexnet/alexnet_custom.py` — 替代乘法版本
- `utils/jpeg_to_Q3.13_txt.py` — JPEG→Q3.13二进制txt转换
- `utils/ifmap_segmentation.py` — Q3.13 ifmap分割为8段(匹配硬件GLB分段)
- `utils/merge_split.py` — 16-bit ↔ 64-bit 格式转换
- `utils/test_segements_4conv.py` — 完整pipeline: resize→Q3.13→segment→64-bit merge

### 缺失的关键组件
**权重提取/量化脚本**不存在。模型目录中的脚本可以消费权重txt文件，但不能生成它们。需要从PyTorch预训练AlexNet提取并量化为Q3.13格式。

## 推荐方案: PyTorch提取

PyTorch的 `torchvision.models.alexnet(weights='IMAGENET1K_V1')` 提供预训练权重，与项目 `alexnet.py` 的维度完全匹配。

### AlexNet Conv层维度 (与项目完全一致)

| 层 | C_in | M_out | Kernel | Filter值数量 | Bias数 |
|----|------|-------|--------|-------------|--------|
| conv1 | 3 | 64 | 11×11 | 23,232 | 64 |
| conv2 | 64 | 192 | 5×5 | 307,200 | 192 |
| conv3 | 192 | 384 | 3×3 | 663,552 | 384 |
| conv4 | 384 | 256 | 3×3 | 884,736 | 256 |
| conv5 | 256 | 256 | 3×3 | 589,824 | 256 |

### 生成脚本思路

```python
import numpy as np
import torch
import torchvision.models as models

# Q3.13参数: FL=13, SCALE=8192, range [-4.0, 3.99988]
model = models.alexnet(weights=models.AlexNet_Weights.IMAGENET1K_V1)
state = model.state_dict()

# Conv层映射: features.0→conv1, features.3→conv2, features.6→conv3,
#             features.8→conv4, features.10→conv5
# PyTorch存储格式: (M, C, H, W) — 与alexnet.py的load_weights完全匹配

for feat_key, name in [("features.0","conv1"), ("features.3","conv2"),
    ("features.6","conv3"), ("features.8","conv4"), ("features.10","conv5")]:
    weight = state[f"{feat_key}.weight"]  # (M, C, H, W)
    bias = state[f"{feat_key}.bias"]      # (M,)
    
    # Q3.13量化: np.int16(round(val * 8192) clamped to [-32768, 32767])
    # 保存为16-bit二进制字符串, 每行一个值
```

## 输入图片处理 (已就绪)

`test_segements_4conv.py` 提供完整ifmap生成流程:
1. Resize图片→227×227
2. JPEG像素→Q3.13 16-bit二进制txt
3. 分割为8段 (每段35行, 7行重叠)
4. 16-bit→64-bit打包 (4个16-bit值合并为一个64-bit字)

硬件需要的64-bit GLB数据已可通过该脚本生成。

## 对照验证方案

生成权重后:
1. PyTorch推理 → 浮点数ofmap (作为精度上限参考)
2. `alexnet.py` 使用Q3.13权重推理 → Q3.13定点ofmap (行为模型参考)
3. 硬件RTL仿真 → 使用同样权重和ifmap → 与步骤2对比

## 其他参考资源

- `github.com/jneless/EyerissF` — Python Eyeriss仿真器 (有LeNet-5 test data, 无AlexNet)
- `github.com/nietzhuang/Cycle-accurate-Eyeriss-model` — SystemC周期精确模型 (参考数据格式)
- `cs.toronto.edu/~guerzhoy/tf_alexnet/` — 权威AlexNet NumPy权重 (bvlc_alexnet.npy)
