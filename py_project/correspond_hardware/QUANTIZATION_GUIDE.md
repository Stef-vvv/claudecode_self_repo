# 量化方案与软硬件对比教学说明

## 1. 量化格式 (Q-Format)

### 定点数表示

Qm.n 格式: m位整数 + n位小数, 总值 = (整数部分) + (小数部分)/2^n

本工程使用的格式（基于read_conv2.py分析）:

| 数据 | 格式 | 位宽 | 步长 | 范围 |
|------|------|------|------|------|
| IFMAP | Q0.8 | 8-bit | 1/256=0.00390625 | [-0.5, 0.49609375] |
| FILTER | Q0.8 | 8-bit | 1/256=0.00390625 | [-0.5, 0.49609375] |
| MAC积 | Q0.16 | 16-bit | 1/65536 | — |
| 累加和 | Q16+ | 24+bit | — | — |
| OFMAP | Q0.8 | 8-bit | 1/256 | [-0.5, 0.49609375] |

### Python端的量化/反量化

```python
# read_conv2.py: 从二进制读取8-bit有符号整数, 除以256得到浮点
def Read(file):
    arr = [int(i) for i in f.read()]
    arr = [i if i < 128 else i - 256 for i in arr]  # 无符号→有符号
    return arr

def Quant(num, Q):
    return num / (2 ** Q)  # 除以256 (Q=8)

# 例: 二进制值 6 → 6/256 = 0.0234375
# 例: 二进制值 -5 (即251) → 251-256=-5 → -5/256 = -0.01953125
```

### 硬件端的量化

```verilog
// 量化: float → Q8 (写入BRAM时)
// Q8_val = clamp(round(float_val * 256), -128, 127)
// 存储为8-bit有符号整数

// MAC: Q8 × Q8 → Q16
wire [15:0] product = data_q8 * weight_q8;  // Q0.8 × Q0.8 = Q0.16

// 累加: 3个product求和, 仍为Q16
wire [17:0] dot = product0 + product1 + product2;  // 3×Q16需要额外2bit

// 输出量化: Q16 → Q8 (右移8位+饱和)
wire [7:0] output_q8 = (dot[17:8] > 8'd127) ? 8'd127 :
                       (dot[17] && |dot[16:8] != 8'd127) ? -8'd128 :  // 负溢出
                       dot[15:8];  // 取Q16的[15:8]位 = 右移8位
```

## 2. 数据如何输入硬件

### BRAM存储格式

**IFMAP BRAM** (128-bit宽度, 每地址存16个Q8值 = 一行):
```
地址0: [ch0_row0_col0, ch0_row0_col1, ..., ch0_row0_col15]  (128-bit = 16×8bit)
地址1: [ch0_row1_col0, ...]
...
地址15: [ch0_row15_col0, ...]
地址16: [ch1_row0_col0, ...]   ← 下一个通道
```

**FILTER BRAM** (32-bit宽度, 每地址存3+1个Q8值):
```
地址0: [f0_c0_kh0_kw0, f0_c0_kh0_kw1, f0_c0_kh0_kw2, 0]  (32-bit = 4×8bit)
地址1: [f0_c0_kh1_kw0, f0_c0_kh1_kw1, f0_c0_kh1_kw2, 0]
地址2: [f0_c0_kh2_kw0, f0_c0_kh2_kw1, f0_c0_kh2_kw2, 0]
地址3: [f0_c1_kh0_*, ...]  ← 下一个输入通道
...
地址96: [f1_c0_kh0_*, ...]  ← 下一个输出通道 (96 = 32ch × 3 rows)
```

### COE文件生成 (Xilinx BRAM初始化)

```python
# 从.real.dat文件生成COE (参考conv2.input.coe, conv2.dat.coe)
# 步骤:
# 1. 读取每行16个Q8浮点值
# 2. 转回整数: int_val = round(val * 256)
# 3. 拼接为128-bit二进制: {int15[7:0], int14[7:0], ..., int0[7:0]}
# 4. 写入COE格式
```

## 3. 软硬件对比: 如何验证RTL与Python一致

### 3.1 PE层对比

| 步骤 | Python (pe.py) | RTL (pe.v) | 验证点 |
|------|---------------|-----------|--------|
| 数据锁存 | `self.data = self.in_data.copy()` | `data_r0 <= in_d0` (nxt_data mux) | 输入值相同 |
| 滤波器锁存 | `self.filter = self.in_filter.copy()` | `filt_r0 <= in_f0` (start时无条件) | 输入值相同 |
| MAC点积 | `sum(sw[i]*f[i] for i in range(3))` | `dot0 = d0*f0+d1*f1+d2*f2` | 算术等价 |
| 结果累加 | `[x+y for x,y in zip(in_res, result)]` | `result_r0 + in_r0` | 算术等价 |
| 状态机 | 5状态 (IDLE/MAC/ACC/DONE) | 同左 | 状态跳转一致 |
| 时序 | start拍同时锁存+MAC | 同左 (组合路径) | 周期数一致 |

**验证方法**: 给Python和RTL相同的输入数据, 逐周期比较result寄存器值.
测试用例: data=[1,2,3,4,5], filter=[1,1,1] → 期望 [6,9,12] (4拍后).

### 3.2 PE Array层对比

| 步骤 | Python (pe_array.py) | RTL (pe_array.v) | 验证点 |
|------|---------------------|-----------------|--------|
| 数据广播 | `grid[j][i].in_data = data_port` | `assign data_bus_00 = in_data` (全部9条) | 同一总线值 |
| 滤波器右传 | `grid[j][i].in_filter = grid[j][i-1].filter` | `filt_in_01 = filt_out_00` | 传播方向 |
| 部分和下传 | `grid[j][i].in_result = grid[j-1][i].result` | `psum_in_10 = psum_out_00` | 传播方向 |
| 启动传播 | `grid[j][i].start = above_start or left_start` | `start_11 = os_01 | os_10` | 对角线 |
| 输出选择 | `break on first finished` | `fin_20 ? psum_out_20 : fin_21 ? ...` | 优先列0 |

**硬件vs软件的时序差异**:
- Python: Phase1(所有PE并行process_one) → Phase2(PE间通信). start信号在Phase2传播, 下一拍生效.
- RTL: 所有assign是组合逻辑, out_start在posedge更新, 同一拍传播到邻PE的start. 由于NBA调度机制, 邻PE在本拍不会误触发.

### 3.3 精度对比

| 计算阶段 | Python (float) | RTL (integer) | 精度差异 |
|----------|---------------|---------------|----------|
| MAC点积 | float × float → float | Q8 × Q8 → Q16 (integer) | float有舍入, integer精确 |
| 多通道累加 | float += float (累积误差) | Q16累加器, 最后>>8 | integer无累积误差 |
| 最终输出 | float (与Q8 golden有1-2LSB偏差) | Q8 (bit-exact匹配golden) | RTL精确匹配 |

**RTL精度优势**: 整数算术无浮点舍入, 累加全精度, 仅在最后输出时右移8位量化. 这是RTL输出能与golden reference 100%匹配的原因.

## 4. 量化位宽设计原理

```
输入数据 Q0.8:     d₇ d₆ d₅ d₄ d₃ d₂ d₁ d₀  (8-bit, 全小数)
                             ↑ 小数点位置 (0位整数, 8位小数)
权重 Q0.8:         w₇ w₆ w₅ w₄ w₃ w₂ w₁ w₀
乘积 Q0.16:   p₁₅ p₁₄ ... p₈ p₇ ... p₁ p₀  (16-bit, 全小数)
3项求和:    需要额外2-bit (log2(3)≈2) → 18-bit
32ch × 9kw累加: 需要额外 log2(288)≈9-bit → 27-bit
最终输出 Q0.8: 右移8位 + 饱和[-128,127]
```

**硬件位宽选择**:
- PE内部累加器: 建议20-bit (覆盖3×3卷积核内累加)
- Aggregator累加器: 建议32-bit (覆盖32通道×9核位置累加)
- 最终输出: 8-bit Q0.8 (经右移8位和饱和)

**注意**: 当前PE.v使用ACC_WIDTH=16, 对于单PE内3个乘积+3行累加是足够的(最大需要约18-bit). 如果要在PE内做多通道累加, 需要增加位宽.

## 5. Python模型 vs RTL差异总结

| 方面 | Python模型 | RTL实现 |
|------|-----------|---------|
| 数值精度 | float64 | 定点整数 (可配置位宽) |
| 与golden匹配 | ~98% (1-2 LSB偏差) | 100% (bit-exact, 如果正确设计) |
| 时序模型 | process_one()分两阶段 | assign+always (硬件并发) |
| 控制流 | Python for/while循环 | 显式FSM状态机 |
| 数据存储 | Python list引用 | 寄存器/wire + 总线打包 |
| 并行度 | 顺序执行 (单线程) | 9个PE完全并行 |

## 6. 操作步骤: 从激励到输出

### 步骤1: 准备BRAM初始化文件

```bash
# 使用Python脚本将.real.dat转为COE文件
python -c "
import numpy as np
data = np.loadtxt('conv2.input.real.dat')
# 量化到Q8
q8 = np.clip(np.round(data * 256), -128, 127).astype(np.int8)
# 生成128-bit行 (每16个值打包)
# 写入COE格式...
"
```

### 步骤2: 加载到Vivado BRAM IP

使用Block Memory Generator, 配置为:
- IFMAP: 128-bit宽, 512深度 (32ch×16rows=512)
- FILTER: 32-bit宽, 6144深度 (64×32×3=6144)
- OFMAP: 128-bit宽, 1024深度 (64×16=1024)

### 步骤3: 运行RTL仿真

```bash
# Vivado仿真
xvlog pe.v pe_array.v scheduler.v tb_top.v
xelab -L xil_defaultlib -s top_sim tb_top
xsim top_sim -R
```

### 步骤4: 对比输出

```bash
# 从BRAM dump输出, 与golden reference对比
python -c "
rtl_out = read_bram_dump('rtl_output.dat')
golden = np.loadtxt('conv2.output.real.dat')
diff = np.abs(rtl_out - golden)
print(f'Exact match: {np.sum(diff<1e-10)}/{len(golden)}')
"
```

期望: RTL使用整数算术, 应与golden 100%匹配.
