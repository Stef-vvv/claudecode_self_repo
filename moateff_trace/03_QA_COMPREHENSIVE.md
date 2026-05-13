# 全面解答：AlexNet激励生成 & 硬件对接流程

---

## Q0: 为什么分段？8段是怎么来的？

### 问题
为什么Conv1 ifmap 227×227×3 "超出GLB单次加载容量，需分8段加载"？35行、重叠7行是什么？为什么有"+3"？

### 答案

**根本原因：GLB放不下整个ifmap。**

Conv1 ifmap大小 = 3 × 227 × 227 = 154,587 个像素
每个像素16-bit Q3.13 = 2 bytes
总共 = 154,587 × 2 = 309,174 bytes ≈ **302 KB**

而 RTL 中 IFMAP_GLB 的深度是 7945 个 16-bit 条目：
```
IFMAP_GLB 容量 = 7945 × 16 bit = 127,120 bits ≈ 15.5 KB
```

302 KB >> 15.5 KB！所以一次只能加载 ifmap 的一部分（一个"段"）。

**分段策略来自 Eyeriss 论文 JSSC 2017 Section V-A**：

论文描述的就是对 ifmap 进行分段处理。每段的计算方式是：
- 每段处理 `e = 7` 行 ofmap
- 对应需要的 ifmap 行数 = `(e-1)×U + R = (7-1)×4 + 11 = 24 + 11 = 35` 行

对于 227 行 ifmap，Conv1 stride=4，U=4：
- 每段产生 7 行 ofmap（7×4 = 28 行 ifmap 的非重叠部分）
- 但需要 35 行 ifmap（因为 11×11 滤波器需要额外的 7 行上下文）
- 所以相邻段之间重叠 = 35 - 28 = 7 行

**8段是怎么来的？**

Ceil(227 / 28) = Ceil(8.107) → 需要 >8 个非重叠块。实际上：
- 段1: ifmap行 [0, 35) 
- 段2: ifmap行 [28, 63)  (重叠行[28,35))
- 段3: ifmap行 [56, 91)
- ...
- 段8: ifmap行 [196, 227) = 31 行（最后一段不足35行）

共 8 段覆盖全部 227 行。最后一段只有 31 行是因为已经到了 ifmap 底部。

**"还有3" 是什么？**

Ceil(227/28) = 9（如果按28行为单位），但实际只用了8段。因为 227 = 28×8 + 3，最后 3 行被第8段覆盖。这个"+3"不是"多加3段"，而是"227除以28余3行"。

---

## Q1: 权重是针对这一张图片的吗？

### 答案：不是！

**权重是 ImageNet 预训练的，与测试图片无关。**

AlexNet 是在 ImageNet 数据集上训练的（120万张图片，1000个类别）。训练完成后，权重就固定了。

```
训练阶段（PyTorch/ImageNet, 120万张图片）  →  得到 AlexNet 权重
                                                      ↓
我们的测试图片（1张花/狗照片）                   使用相同的权重做推理
                                                      ↓
                                              得到 ofmap 输出
```

我们的测试图片只是**输入**。权重是"知识"——AlexNet学到的"如何识别图像特征"的编码。无论输入什么图片，权重都不变。

就像你已经学会认字（权重固定），现在给你看一篇新文章（测试图片），你用自己的知识去理解它——你的"认字能力"不会因为看不同的文章而改变。

---

## Q2: 有没有Python行为级输出？拿什么和硬件对比？

### 答案：现在有了！

运行的就是作者的 `convolution.py` 的卷积逻辑（Q3.13定点MAC），生成了：

| 文件 | 内容 | 用途 |
|------|------|------|
| `output/conv1_ofmap_q313_golden.txt` | Conv1输出 55×55×64=193,600值 | **Golden Reference** |
| `output/conv1_ofmap_64_golden.txt` | 同上，64-bit packed | 与硬件输出直接比较 |

**对比方式**：
```
1. 运行 Python Conv1 → output/conv1_ofmap_q313_golden.txt  (行为模型)
2. 运行 硬件仿真 → tb 读取 ifmap + weights → PE 阵列计算 → ofmap 输出文件
3. 逐像素对比: 如果全部匹配 → 硬件正确
               如果有差异 → 逐值定位问题
```

---

## Q3: 你用了原作者的 model/ 代码吗？作者缺了什么，你补充了什么？

### 我用了什么

| 使用 | 未使用 |
|------|--------|
| `scripts/convolution.py` 的 Q3.13 定点 MAC 算法 | 未用 `alexnet.py`（需要完整5层+FC权重，太重） |
| `utils/jpeg_to_Q3.13_txt.py` 的转换逻辑 | 未用交互式脚本（太繁琐） |
| `utils/merge_split.py` 的 64-bit 打包逻辑 | |
| `utils/ifmap_segmentation.py` 的分段逻辑 | |

### 作者缺了什么

作者的项目期望以下文件存在，但**从未提供**：
```
conv1_filter_16.txt      ← 23,232 个 Q3.13 权重值
conv1_bias_16.txt        ← 64 个 Q3.13 偏置值
conv2_filter_16.txt      ← 307,200 个值
...                       (conv2-5 同理)
```

`alexnet.py` 第204行的 `load_weights()` 函数会读这些文件，但文件本身不存在。作者只写了"消费"代码，没有写"生成"代码。

### 我补充了什么

| 补充 | 方法 |
|------|------|
| 5层权重+偏置 | PyTorch torchvision 预训练 AlexNet → Q3.13 量化 |
| 测试图片 | picsum.photos 下载 → 227×227 转换 |
| Q3.13 ifmap | 图片 → 像素归一化 → Q3.13 16-bit |
| 64-bit GLB格式 | 4×16-bit 打包 → 64-bit |
| 8段ifmap | 按 Eyeriss 论文分段策略切割 |
| Golden Reference | 使用作者 `convolution.py` 的卷积算法计算 55×55×64 ofmap |

---

## Q4: 扫描链是怎么配置的？

### 扫描链是什么

扫描链（Scan Chain）是一大串串行移位寄存器。在计算开始前，把所有配置 bits 逐个移入。配置完成后（scan_en=0），寄存器值锁存，不再改变。

**它配置什么**：
1. 17个参数寄存器：H, W, R, S, E, F, C, M, N, U, m, n, e, p, q, r, t
2. PE使能矩阵 (168 bits)：每个PE是否参与当前层计算
3. NoC路由ID (3,552 bits)：每个PE的 ifmap/filter/ipsum/opsum GIN/GON 标签

### 扫描链是怎么生成的

**不是硬件自己生成的。** 是软件预计算的（论文说的"offline generated"）。

流程：
```
1. 人工确定映射参数: m, n, e, p, q, r, t
   （这些参数决定"如何将卷积层映射到PE阵列"）
   
2. config_script.py 自动计算:
   - 17个参数的二进制表示
   - PE使能矩阵（哪些PE被用到）
   - NoC路由ID（每个PE的标签）
   
3. 生成 serial_data.txt（二进制位流）
   
4. 仿真时 scan_en=1, 每个时钟移入1 bit, 共3644个时钟周期
```

### 扫描链的配置依据

**来自 Eyeriss 论文 Table III + 作者的 config_script.py**。

对于 AlexNet Conv1（论文 JSSC 2017, Table III）:
```
R=11, C=3, M=96, H=227, W=227, E=55, U=4
映射参数: m=64, n=4, e=7, p=16, q=1, r=2, t=2
```

这些映射参数来自论文中的 RS 数据流优化——最大化 PE 利用率同时满足 SPAD 容量约束。

### 你的理解对了一半

你说的"把形状和 m/n/p/q/r/t 一给，硬件自己配出来"——这个"给"的过程就是扫描链。硬件不会自己决定映射参数，是**人（或编译器）预先把参数算好，通过扫描链喂给硬件**。

---

## Q5: 权重和图片怎么来的？

### 权重

```
torchvision.models.alexnet(weights='IMAGENET1K_V1')
                              ↓
PyTorch 自动下载预训练权重文件 (233 MB .pth)
                              ↓
extract_alexnet_weights.py 提取 Conv1-5 层的 weight 和 bias 张量
                              ↓
float32 → Q3.13 int16 量化
                              ↓
conv1_filter_16.txt  (每行一个16-bit二进制字符串)
```

**这是官方的权威 AlexNet 权重**。ImageNet 比赛 2012 年冠军模型。torchvision 提供的 `IMAGENET1K_V1` 权重被数以万计的项目使用和验证过。

### 测试图片

从 picsum.photos（CC0 自由许可）下载的高质量照片，缩放到 227×227：
- `test_flower.jpg` — 紫色花朵（完整画面）
- `test_dog_full.jpg` — 全身边境牧羊犬
- 上一张 `test_image.jpg` — 鼻子特写（不推荐，已替换）

---

## Q6: 完整的使用流程是什么？

### 端到端流程

```
┌─────────────────────────────────────────────────────────────┐
│ 步骤1: 准备权重 (已完成)                                      │
│                                                              │
│ torchvision AlexNet → extract_alexnet_weights.py              │
│   → weights_q313/conv1_filter_16.txt (23,232 values)         │
│   → weights_q313/conv1_bias_16.txt   (64 values)             │
│   → weights_q313/conv1_filter_64.txt (5,808 lines, GLB格式)  │
│   → weights_q313/conv1_bias_64.txt   (16 lines, GLB格式)     │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 步骤2: 准备输入图片 + 生成 Golden Reference (已完成)          │
│                                                              │
│ test_flower.jpg → ifmap Q3.13                                │
│                                                              │
│ Python Conv1 (使用作者的convolution.py算法):                  │
│   ifmap_q313 + weights_q313 + bias_q313 → Q3.13 卷积         │
│   → output/conv1_ofmap_q313_golden.txt (193,600 values)      │
│   → output/conv1_ofmap_64_golden.txt   (48,400 lines)        │
│                                                              │
│ 这就是 Golden Reference —— 硬件正确性的标准答案。            │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 步骤3: 硬件仿真 (待你做)                                      │
│                                                              │
│ 在 testbench 中：                                             │
│   1. $readmemb 加载 ifmap 8段 → GLB IFMAP                    │
│   2. $readmemb 加载 filter_64 → GLB FILTER                   │
│   3. $readmemb 加载 bias_64 → GLB BIAS                       │
│   4. 加载 scan chain 配置                                     │
│   5. 启动 scheduler (start=1)                                 │
│   6. 等待 done=1                                              │
│   7. 读取 GLB PSUM 输出                                       │
│   8. 写入 ofmap_hw_output.txt                                 │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 步骤4: 对比验证 (待你做)                                      │
│                                                              │
│ diff output/conv1_ofmap_q313_golden.txt ofmap_hw_output.txt  │
│   或                                                         │
│ 逐值比较: match / mismatch                                    │
│                                                              │
│ 全部匹配 → 硬件 Conv1 正确！                                  │
│ 有差异 → 定位差异出现的像素位置，debug                        │
└─────────────────────────────────────────────────────────────┘
```

### 需要对比的文件

| 文件 | 来源 | 格式 |
|------|------|------|
| `output/conv1_ofmap_q313_golden.txt` | Python Conv1 | 16-bit 二进制, 每行1值, 共193,600行 |
| `ofmap_hw_output.txt` | 硬件仿真输出 | 同上格式 |

两个文件的行数、值序、格式完全一致，可以直接 `diff` 或逐行比较。

---

## Q7: 关于上一张图片（鼻子）

你说得对，picsum ID#40 确实是狗鼻子特写（一只棕色狗的鼻子占据了整个画面），不是好的测试图片。

已替换为：
- `test_flower.jpg` (picsum ID#106) — **紫色花朵，完整画面**，纹理丰富
- `test_dog_full.jpg` (picsum ID#237) — **边境牧羊犬全身**，清晰的物体

推荐用 `test_flower.jpg` 作为演示——花草植物是 ImageNet 1000类中的标准类别（如 "daisy", "sunflower"），AlexNet 对此类图片有良好的特征响应。

---

## 补充文件清单

```
alxnet_training/
├── output/
│   ├── conv1_ofmap_q313_golden.txt    ← ★ 193,600 行 Golden Reference
│   └── conv1_ofmap_64_golden.txt      ← ★ 48,400 行 (64-bit packed)
├── ifmap_data/
│   ├── conv1_ifmap_q313_flower.txt    ← 154,587 行 ifmap (花朵)
│   └── conv1_ifmap_flower_seg{1-8}_64.txt  ← 8段 64-bit 硬件格式
├── weights_q313/
│   ├── conv1_filter_16.txt            ← 23,232 行 (16-bit)
│   ├── conv1_bias_16.txt              ← 64 行
│   ├── conv1_filter_64.txt            ← 5,808 行 (64-bit GLB)
│   └── conv1_bias_64.txt              ← 16 行
├── test_flower.jpg                    ← ★ 测试图片 (紫色花朵, 227×227)
└── test_dog_full.jpg                  ← 备选 (边境牧羊犬)
```
