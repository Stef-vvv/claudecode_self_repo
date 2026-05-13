# Q6: GLB Depth Numbers — Why These Values?

## 1. Parameters from `shared_pkg.sv` (lines 182-185)

```systemverilog
parameter IFMAP_GLB_DEPTH  = 7945;
parameter FILTER_GLB_DEPTH = 3872;
parameter PSUM_GLB_DEPTH   = 46656;
parameter BIAS_GLB_DEPTH   = 64;
```

All depths are in units of **16-bit entries** (matching the GLB's native storage width at port B).

## 2. AlexNet CONV1 Parameters (from `shared_pkg.sv`, lines 19-38)

```
Shape parameters (full layer):
  H=227, W=227, R=11, S=11, E=55, F=55
  C=3 (input channels), M=64 (output channels), N=4, U=4 (stride)

Tiling parameters (per tile/pass):
  m=64 (ofmap filters per tile)
  n=1  (ifmap channels per pass)
  e=7  (ofmap rows per tile)
  p=16 (filters per PE group)
  q=1  (ifmap channels per PE group)
  r=1  (filter rows per PE group)
  t=2  (filter channel groups per PE)
```

## 3. IFMAP_GLB_DEPTH = 7945

### Derivation

The ifmap GLB stores one tile of input feature map data. For one processing tile:

- **n = 1** ifmap channel processed per pass
- **e = 7** output rows per tile
- **U = 4** stride
- **R = 11** filter height
- **W = 227** input width

The input rows needed to compute `e` output rows with stride `U` and filter height `R`:

```
input_rows = (e - 1) * U + R
          = (7 - 1) * 4 + 11
          = 6 * 4 + 11
          = 24 + 11
          = 35
```

(This matches `CONV1_D = 35` in shared_pkg, which represents the ifmap depth dimension.)

Total ifmap pixels needed per tile:

```
IFMAP_GLB_DEPTH = n * input_rows * W
                = 1 * 35 * 227
                = 7,945
```

**Matches exactly: 7945.**

### With 64-bit Packing

GLB port A (DRAM write side) packs 4 x 16-bit pixels into each 64-bit word. Number of 64-bit entries needed:

```
ceil(7945 / 4) = 1,987 entries at 64-bit width
```

Each `dual_bram` depth = `IFMAP_GLB_DEPTH / 4 = 7945 / 4 = 1986.25 -> 1987` entries.

### General Formula

```
IFMAP_GLB_DEPTH = n * ((e - 1) * U + R) * W
```

Maximum across all CONV layers (from shared_pkg CONV1-CONV5): CONV1 has the largest at 7945.

## 4. FILTER_GLB_DEPTH = 3872

### Derivation

The filter GLB stores one tile of filter weights. The filter tile is organized in 4 dimensions (from `filter_noc_controller.sv`):

```
dim4 = p * t   (filter groups across PEs)
dim3 = q * r   (channel groups)
dim2 = R        (filter rows)
dim1 = S        (filter columns)
```

For CONV1:

```
p = 16, t = 2  => dim4 = 16 * 2 = 32
q = 1,  r = 1  => dim3 = 1 * 1 = 1
R = 11          => dim2 = 11
S = 11          => dim1 = 11

FILTER_GLB_DEPTH = dim4 * dim3 * dim2 * dim1
                 = 32 * 1 * 11 * 11
                 = 32 * 121
                 = 3,872
```

**Matches exactly: 3872.**

### General Formula

```
FILTER_GLB_DEPTH = p * t * q * r * R * S
```

This represents all filter weights needed for one complete tile of computation. Note that `p*t = 32` means 32 filters are active in the tile (distributed as 16 filters/PE * 2 filter groups).

CONV1 has the largest filter requirement (R=S=11 are the largest filters across CONV1-5).

## 5. PSUM_GLB_DEPTH = 46656

### Derivation

The psum GLB stores partial sums (intermediate output accumulations) across input channel passes. For a given tile:

```
PSUM_GLB_DEPTH = e * F * m
```

This must hold all partial sums for the current output tile. Let's check across all CONV layers:

**CONV1**: e=7, F=55, m=64 => 7 * 55 * 64 = **24,640**
**CONV2**: e=27, F=27, m=64 => 27 * 27 * 64 = **46,656** <-- LARGEST
**CONV3**: e=13, F=13, m=64 => 13 * 13 * 64 = **10,816**
**CONV4**: e=13, F=13, m=64 => 13 * 13 * 64 = **10,816**
**CONV5**: e=13, F=13, m=64 => 13 * 13 * 64 = **10,816**

**CONV2 has the largest psum requirement: 46,656 entries.**

The PSUM_GLB_DEPTH is therefore dimensioned for the **worst-case layer** (CONV2) across all supported configurations.

### Verification of CONV2 e=27

CONV2 parameters: E=27, F=27, M=192, m=64, e=27.

Since `e = E = 27`, the entire output height fits in one tile (no vertical tiling needed for CONV2). All 27 output rows x 27 output cols x 64 output channels = 46,656 partial sums need simultaneous storage.

### Why 46656 = 216^2

Interesting numerical property: `46656 = 6^6 = 216^2 = 64 * 729 = 2^6 * 3^6`.

### With 16-bit entries

Each psum value is 16-bit. Total psum storage: 46656 * 16 bits = 746,496 bits = 93,312 bytes = ~91 KB. This is close to the paper's 100 KB total GLB, confirming psum is the dominant storage consumer.

### General Formula

```
PSUM_GLB_DEPTH = max_{all layers}(e * F * m)
```

Where `m` is the number of output channels processed per tile.

## 6. BIAS_GLB_DEPTH = 64

### Derivation

One bias value per output channel per m-tile:

```
BIAS_GLB_DEPTH = max(m) across all layers
```

Looking at the tiling parameters in `shared_pkg.sv`:

| Layer | m |
|-------|---|
| CONV1 | 64 |
| CONV2 | 64 |
| CONV3 | 64 |
| CONV4 | 64 |
| CONV5 | 64 |

All layers use `m = 64`. The bias GLB stores 64 x 16-bit bias values.

### Why not larger for M=384 (CONV3)?

CONV3 has M=384 output channels, but `m=64` means only 64 channels are processed per tile. The scheduler loads biases for the current m-tile, processes it, then loads biases for the next tile. So only 64 bias entries are needed at any time.

### General Formula

```
BIAS_GLB_DEPTH = max(m) = 64
```

## 7. Tiny Test Layer: Minimum GLB Depths

Tiny test parameters (`config/tiny/parameters.txt`):

```
H=8, W=8, R=3, S=3, E=6, F=6
C=1, M=1, N=1, U=1
m=1, n=1, e=6, p=1, q=1, r=1, t=1
```

### IFMAP_GLB_DEPTH (min)

```
input_rows = (e - 1) * U + R = (6-1) * 1 + 3 = 5 + 3 = 8
IFMAP = n * input_rows * W = 1 * 8 * 8 = 64
```

**Minimum: 64 entries**

### FILTER_GLB_DEPTH (min)

```
FILTER = p * t * q * r * R * S = 1 * 1 * 1 * 1 * 3 * 3 = 9
```

**Minimum: 9 entries** (just nine 3x3 filter weights)

### PSUM_GLB_DEPTH (min)

```
PSUM = e * F * m = 6 * 6 * 1 = 36
```

**Minimum: 36 entries** (6x6 output feature map, 1 channel)

### BIAS_GLB_DEPTH (min)

```
BIAS = m = 1
```

**Minimum: 1 entry**

### Summary Table

| GLB | CONV1 (AlexNet) Depth | Tiny Test Min Depth | Ratio |
|-----|----------------------|---------------------|-------|
| IFMAP | 7,945 | 64 | 124x |
| FILTER | 3,872 | 9 | 430x |
| PSUM | 46,656 (CONV2 max) | 36 | 1,296x |
| BIAS | 64 | 1 | 64x |

The tiny test requires dramatically less GLB storage. The parameterized depths in `shared_pkg.sv` are sized for the full AlexNet workloads, not the tiny test.

## 8. Full Calculations for AlexNet CONV1 (with 64-bit packing)

Assuming data is packed at 64-bit (4 x 16-bit) for DRAM transfers:

### IFMAP: 3 x 227 x 227

Raw pixels: 3 * 227 * 227 = 154,587 pixels
64-bit entries: ceil(154,587 / 4) = 38,647 entries

But the GLB only stores ONE TILE at a time (not the entire layer):
- Tile: n=1 channel, 35 rows, 227 cols = 7,945 pixels
- 64-bit entries for tile: ceil(7945/4) = 1,987

### FILTER: 64 x 3 x 11 x 11

Raw weights: 64 * 3 * 11 * 11 = 23,232 weights
64-bit entries for full layer: ceil(23,232 / 4) = 5,808 entries

GLB tile only: 3,872 weights (for m=64, 1 channel group, 32 filter groups)

### OFMAP: 64 x 55 x 55

Raw outputs: 64 * 55 * 55 = 193,600 values
64-bit entries: ceil(193,600 / 4) = 48,400 entries

PSUM GLB only stores one tile: e=7 * F=55 * m=64 = 24,640 values (for CONV1)

### BIAS: 64

64 bias values -> ceil(64/4) = 16 entries at 64-bit, or 64 entries at 16-bit.

## 9. Key Design Insight

The GLB depths are **tile-sized, not layer-sized**. The Eyeriss architecture processes convolution in tiles:
1. Load one ifmap tile into GLB
2. Load corresponding filter tile into GLB
3. Process tile -> partial sums stored in PSUM GLB
4. Repeat for next tile/input-channel pass, accumulating in PSUM GLB
5. When tile complete, dump PSUM GLB to DRAM

The scheduler (`scheduler.sv`) orchestrates this tiling loop. The GLB only needs to be large enough for the **largest single tile** across all layers. This is a fundamental efficiency of the row-stationary dataflow: it minimizes on-chip storage by tiling.



















**第六季度问题：GLB 深度数值 — 为什么是这些值？**

**1. 来自 `shared_pkg.sv` 的参数（第182-185行）**

```systemverilog
parameter IFMAP_GLB_DEPTH  = 7945;
parameter FILTER_GLB_DEPTH = 3872;
parameter PSUM_GLB_DEPTH   = 46656;
parameter BIAS_GLB_DEPTH   = 64;
```

所有深度均以 **16位条目** 为单位（与GLB在端口B上的原生存储宽度相匹配）。

**2. AlexNet CONV1 参数（来自 `shared_pkg.sv`，第19-38行）**

```
形状参数（完整层）：
  H=227, W=227, R=11, S=11, E=55, F=55
  C=3（输入通道数），M=64（输出通道数），N=4，U=4（步长）

分块参数（每块/每趟）：
  m=64（每块的ofmap滤波器数）
  n=1（每趟的ifmap通道数）
  e=7（每块的ofmap行数）
  p=16（每个PE组的滤波器数）
  q=1（每个PE组的ifmap通道数）
  r=1（每个PE组的滤波器行数）
  t=2（每个PE的滤波器通道组数）
```

**3. IFMAP_GLB_DEPTH = 7945**

**推导过程**

ifmap GLB存储一个分块的输入特征图数据。对于一个处理分块来说：

-   **n = 1** 每趟处理的ifmap通道数
-   **e = 7** 每块的输出行数
-   **U = 4** 步长
-   **R = 11** 滤波器高度
-   **W = 227** 输入宽度

生成 `e` 行输出所需的输入行数（步长为 `U`，滤波器高度为 `R`）：

```
input_rows = (e - 1) * U + R
          = (7 - 1) * 4 + 11
          = 6 * 4 + 11
          = 24 + 11
          = 35
```

（这与 shared_pkg 中代表ifmap深度维度的 `CONV1_D = 35` 相匹配。）

每块所需的ifmap像素总数：

```
IFMAP_GLB_DEPTH = n * input_rows * W
                = 1 * 35 * 227
                = 7,945
```

**精确匹配：7945。**

**使用64位打包时**

GLB端口A（DRAM写侧）将 4 x 16位像素打包到每个64位字中。所需的64位条目数：

```
ceil(7945 / 4) = 1,987 条 64位宽度的条目
```

每个 `dual_bram` 的深度 = `IFMAP_GLB_DEPTH / 4 = 7945 / 4 = 1986.25 -> 1987` 条目。

**通用公式**

```
IFMAP_GLB_DEPTH = n * ((e - 1) * U + R) * W
```

所有CONV层（来自 shared_pkg 的 CONV1-CONV5）中的最大值：CONV1 最大，为 7945。

**4. FILTER_GLB_DEPTH = 3872**

**推导过程**

滤波器GLB存储一个分块的滤波器权重。滤波器分块在4个维度上组织（来自 `filter_noc_controller.sv`）：

```
dim4 = p * t   （跨PE的滤波器组）
dim3 = q * r   （通道组）
dim2 = R        （滤波器行）
dim1 = S        （滤波器列）
```

对于 CONV1：

```
p = 16, t = 2  => dim4 = 16 * 2 = 32
q = 1,  r = 1  => dim3 = 1 * 1 = 1
R = 11          => dim2 = 11
S = 11          => dim1 = 11

FILTER_GLB_DEPTH = dim4 * dim3 * dim2 * dim1
                 = 32 * 1 * 11 * 11
                 = 32 * 121
                 = 3,872
```

**精确匹配：3872。**

**通用公式**

```
FILTER_GLB_DEPTH = p * t * q * r * R * S
```

这代表了一个完整计算分块所需的所有滤波器权重。注意，`p*t = 32` 意味着该分块中有32个滤波器处于活跃状态（分布为每个PE 16个滤波器 * 2个滤波器组）。

CONV1具有最大的滤波器需求（在 CONV1-5 中 R=S=11 是最大的滤波器尺寸）。

**5. PSUM_GLB_DEPTH = 46656**

**推导过程**

psum GLB存储跨输入通道趟的部分和（中间输出累积）。对于一个给定的分块：

```
PSUM_GLB_DEPTH = e * F * m
```

这必须为当前输出分块保存所有部分和。让我们检查所有 CONV 层：

**CONV1**：e=7, F=55, m=64 => 7 * 55 * 64 = **24,640**
**CONV2**：e=27, F=27, m=64 => 27 * 27 * 64 = **46,656** <-- 最大
**CONV3**：e=13, F=13, m=64 => 13 * 13 * 64 = **10,816**
**CONV4**：e=13, F=13, m=64 => 13 * 13 * 64 = **10,816**
**CONV5**：e=13, F=13, m=64 => 13 * 13 * 64 = **10,816**

**CONV2 具有最大的psum需求：46,656 条目。**

因此，PSUM_GLB_DEPTH 是按所有支持配置中的 **最坏情况层**（CONV2）来确定尺寸的。

**验证 CONV2 e=27**

CONV2 参数：E=27，F=27，M=192，m=64，e=27。

由于 `e = E = 27`，整个输出高度适配在一个分块中（CONV2 不需要垂直分块）。所有 27 个输出行 x 27 个输出列 x 64 个输出通道 = 46,656 个部分和需要同时存储。

**为什么 46656 = 216^2**

有趣的数值性质：`46656 = 6^6 = 216^2 = 64 * 729 = 2^6 * 3^6`。

**使用16位条目时**

每个psum值是16位的。psum存储总量：46656 * 16 比特 = 746,496 比特 = 93,312 字节 = ~91 KB。这接近论文中100 KB的总GLB容量，证实了psum是主要的存储消耗者。

**通用公式**

```
PSUM_GLB_DEPTH = max_{所有层}(e * F * m)
```

其中 `m` 是每块处理的输出通道数。

**6. BIAS_GLB_DEPTH = 64**

**推导过程**

每个m分块中，每个输出通道一个偏置值：

```
BIAS_GLB_DEPTH = max(m) 跨所有层
```

查看 `shared_pkg.sv` 中的分块参数：

| 层 | m |
|---|---|
| CONV1 | 64 |
| CONV2 | 64 |
| CONV3 | 64 |
| CONV4 | 64 |
| CONV5 | 64 |

所有层都使用 `m = 64`。偏置GLB存储 64 x 16位 的偏置值。

**为什么 CONV3 的 M=384 时不是更大？**

CONV3有 M=384 个输出通道，但 `m=64` 意味着每块只处理64个通道。调度器为当前的m分块加载偏置，处理它，然后为下一个分块加载偏置。因此在任何时刻只需要64个偏置条目。

**通用公式**

```
BIAS_GLB_DEPTH = max(m) = 64
```

**7. 微型测试层：最小 GLB 深度**

微型测试参数（`config/tiny/parameters.txt`）：

```
H=8, W=8, R=3, S=3, E=6, F=6
C=1, M=1, N=1, U=1
m=1, n=1, e=6, p=1, q=1, r=1, t=1
```

**IFMAP_GLB_DEPTH（最小值）**

```
input_rows = (e - 1) * U + R = (6-1) * 1 + 3 = 5 + 3 = 8
IFMAP = n * input_rows * W = 1 * 8 * 8 = 64
```

**最小值：64 条目**

**FILTER_GLB_DEPTH（最小值）**

```
FILTER = p * t * q * r * R * S = 1 * 1 * 1 * 1 * 3 * 3 = 9
```

**最小值：9 条目**（仅9个3x3滤波器权重）

**PSUM_GLB_DEPTH（最小值）**

```
PSUM = e * F * m = 6 * 6 * 1 = 36
```

**最小值：36 条目**（6x6输出特征图，1个通道）

**BIAS_GLB_DEPTH（最小值）**

```
BIAS = m = 1
```

**最小值：1 条目**

**汇总表**

| GLB | CONV1 (AlexNet) 深度 | 微型测试最小深度 | 比率 |
|---|---|---|---|
| IFMAP | 7,945 | 64 | 124倍 |
| FILTER | 3,872 | 9 | 430倍 |
| PSUM | 46,656 (CONV2 最大) | 36 | 1,296倍 |
| BIAS | 64 | 1 | 64倍 |

微型测试所需的GLB存储量显著减少。`shared_pkg.sv` 中的参数化深度是为完整的 AlexNet 工作负载确定尺寸的，而不是为微型测试。

**8. AlexNet CONV1 的完整计算（使用64位打包时）**

假设数据以64位（4 x 16位）打包用于DRAM传输：

**IFMAP：3 x 227 x 227**

原始像素：3 * 227 * 227 = 154,587 像素
64位条目：ceil(154,587 / 4) = 38,647 条目

但GLB一次只存储 **一个分块**（而不是整个层）：
-   分块：n=1 通道，35 行，227 列 = 7,945 像素
-   分块的64位条目：ceil(7945/4) = 1,987

**FILTER：64 x 3 x 11 x 11**

原始权重：64 * 3 * 11 * 11 = 23,232 权重
完整层的64位条目：ceil(23,232 / 4) = 5,808 条目

GLB仅存储分块：3,872 权重（用于 m=64，1个通道组，32个滤波器组）

**OFMAP：64 x 55 x 55**

原始输出：64 * 55 * 55 = 193,600 值
64位条目：ceil(193,600 / 4) = 48,400 条目

PSUM GLB 仅存储一个分块：e=7 * F=55 * m=64 = 24,640 值（对于 CONV1）

**BIAS：64**

64 个偏置值 -> ceil(64/4) = 16 条目（64位宽度时），或 64 条目（16位宽度时）。

**9. 关键设计洞察**

GLB深度是 **分块大小的，而不是层大小的**。Eyeriss架构以分块方式处理卷积：
1.  将一个ifmap分块加载到GLB中
2.  将相应的滤波器分块加载到GLB中
3.  处理分块 -> 部分和存储在PSUM GLB中
4.  为下一个分块/输入通道趟重复，在PSUM GLB中累积
5.  当分块完成时，将PSUM GLB转储到DRAM

调度器（`scheduler.sv`）编排此分块循环。GLB只需要足够大，以容纳所有层中 **最大的单个分块**。这是行平稳数据流的一个基本效率之处：它通过分块将片上存储最小化。