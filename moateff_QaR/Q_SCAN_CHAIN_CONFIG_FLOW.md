# 扫描链配置完整流程

## 核心问题

轮卷积开始前，需要预先把"这个卷积层怎么映射到PE阵列上的所有配置信息"喂给硬件。

## 一、配置哪些内容？

### 第1部分：17个CNN参数（92 bits）

| 参数 | 位宽 | 含义 | 示例(Conv1) |
|------|------|------|-----------|
| H | 8 | ifmap高度 | 227 |
| W | 8 | ifmap宽度 | 227 |
| R | 4 | filter高度 | 11 |
| S | 4 | filter宽度 | 11 |
| E | 6 | ofmap高度 | 55 |
| F | 6 | ofmap宽度 | 55 |
| C | 10 | 输入通道数 | 3 |
| M | 10 | 输出通道数 | 96 |
| N | 3 | batch大小 | 4 |
| U | 3 | 步长 | 4 |
| m | 8 | 滤波器tile块 | 64 |
| n | 3 | ifmap tile块 | 4 |
| e | 6 | OFM tile高度 | 7 |
| p | 5 | PE水平并行度 | 16 |
| q | 3 | 通道并行度 | 1 |
| r | 2 | 通道组数 | 2 |
| t | 3 | 滤波器组数 | 2 |

### 第2部分：PE阵列配置（3552 bits）

12行×14列=168 PE，每个PE需要配置：

| 配置项 | 每PE bit数 | 总bit数 |
|--------|-----------|---------|
| enable | 1 | 168 |
| ipsum_ln_sel | 1 | 168 |
| opsum_ln_sel | 1 | 168 |
| ifmap GIN ID | row(4)+col(5)=9 | 888 |
| filter GIN ID | row(4)+col(4)=8 | 720 |
| ipsum GIN ID | row(4)+col(4)=8 | 720 |
| opsum GON ID | row(4)+col(4)=8 | 720 |

**总计: 92 + 3552 = 3644 bits (tiny层)**

## 二、硬件扫描链如何接收（scan_chain.sv）

硬件是一串首尾相连的移位寄存器：

```
scan_in → [H_reg:8bit] → [W_reg:8bit] → [R_reg:4bit] → ... → [t_reg:3bit] → scan_out
```

每个寄存器是 `scan_ff_Nbit`：当 `scan_en=1` 时，每个negedge clk向右移1位。`scan_en=0` 时锁存。

参数寄存器顺序（RTL固定）：
```
H → W → R → S → E → F → C → M → N → U → m → n → e → p → q → r → t
```

后续再接PE阵列的扫描链（在pe_array.sv中，通过scan_w信号串联）。

## 三、配置文件怎么生成（config_script.py）

### 输入：8个txt文件

| 文件 | 内容 | 示例 |
|------|------|------|
| parameters.txt | 17个参数 key=value | H=227, W=227, ... |
| enables.txt | 12×14 0/1矩阵 | 1 1 1 ... 0 0 |
| ipsum_ln_selectors.txt | 12×14 0/1矩阵 | 0 0 1 ... 0 0 |
| opsum_ln_selectors.txt | 12×14 0/1矩阵 | 1 1 0 ... 0 0 |
| ifmap_ids.txt | 12行, 每行15个数 | 0 0 1 2 ... |
| filters_ids.txt | 12行, 每行15个数 | 0 1 2 3 ... |
| ipsum_ids.txt | 12行, 每行15个数 | 0 1 2 3 ... |
| opsum_ids.txt | 12行, 每行15个数 | 0 1 2 3 ... |

### 处理流程

```python
# 1. 将17个参数按位宽拼接 → 92-bit二进制串
parameters = ""
for key in [H,W,R,S,E,F,C,M,N,U,m,n,e,p,q,r,t]:
    parameters += format(val, f'0{width}b')

# 2. 将7个PE配置文件按矩阵逐行拼接
enables       = flatten_matrix("enables.txt")        # 168 bits
ipsum_ln_sel  = flatten_matrix("ipsum_ln_selectors") # 168 bits
opsum_ln_sel  = flatten_matrix("opsum_ln_selectors") # 168 bits
ifmap_ids     = flatten_ifmap_ids("ifmap_ids.txt")   # 888 bits
filter_ids    = flatten_col_ids("filters_ids.txt")   # 720 bits
ipsum_ids     = flatten_col_ids("ipsum_ids.txt")     # 720 bits
opsum_ids     = flatten_col_ids("opsum_ids.txt")     # 720 bits

# 3. 拼接完整链
full_chain = parameters + enables + ipsum_ln_sel + opsum_ln_sel + ifmap_ids + filter_ids + ipsum_ids + opsum_ids

# 4. 生成两个输出文件
# scan_chain.txt: 正向, 每行一个bit
for bit in full_chain:
    write(bit + "\n")

# serial_data.txt: 反向, 每行一个bit (BUG: 第一位写了两次!)
reversed_chain = list(reversed(full_chain))
write(reversed_chain[0] + "\n")   # ← BUG: 单独写了一次
for bit in reversed_chain:         # ← 又写了一次
    write(bit + "\n")
```

### 输出两个文件

| 文件 | 顺序 | 用途 |
|------|------|------|
| scan_chain.txt | forward (MSB-first) | 未使用 |
| serial_data.txt | **reversed + 重复首bit** | TB加载 |

**serial_data.txt格式**: 每行一个"0"或"1"，3644 bits → 3645行（因重复bug）。**位序反转**：full_chain的最后一位在最前面。

## 四、TB如何加载到硬件

```systemverilog
// cfg_pkg.sv → cfg_scan_chain("serial_data.txt")
scan_en = 1;
while (!feof) {
    bit = $sscanf(line, "%d");  // 读一行 → 0或1
    scan_in = bit;
    wait_core_cycle(1);         // 等一个negedge→移位1位
}
scan_en = 0;  // 锁存
```

每个时钟周期把1个bit移入scan_in，扫描链内所有bit向右移1位。

## 五、已知BUG

### Bug 1: serial_data.txt首bit重复 (config_script.py 第170行)

```python
f.write(f'{reversed_chain[0]}\n')  # 第一次
for bit in reversed_chain:
    f.write(f'{bit}\n')            # 第二次(含reversed_chain[0])
```

这导致`serial_data.txt`比预期多1行，所有后续bit偏移1位。**影响e/p/q/r/t参数和全部PE配置**。

实测验证(v4): H/W/R/S/E/F/C/M/N/U/m/n正确，但e=24(应为6)、p=4(应为1)、q=5(应为1)、r=0(应为1)、t=6(应为1)。

### Bug 2: 反转顺序

`reversed(full_chain)` 将整个3644-bit串反转。如果硬件期望MSB-first而软件输出LSB-first（或反之），整个配置就完全错乱。但作者选择反转是因为硬件移位方向与软件拼接方向相反——这是设计意图，不是bug。

## 六、完整配置流程总结

```
┌─────────────────────────────────────────────────────────────┐
│ 离线准备 (config_script.py)                                  │
│                                                              │
│ parameters.txt + enables.txt + ... 7个文件                    │
│         ↓                                                    │
│  拼接为3644-bit二进制串                                       │
│         ↓                                                    │
│  反转 + 每行1bit → serial_data.txt                            │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ TB加载 (cfg_pkg.sv)                                          │
│                                                              │
│  scan_en=1                                                   │
│  for each bit in serial_data.txt:                            │
│    scan_in = bit; @(posedge core_clk);                       │
│  scan_en=0                                                   │
│         ↓ (硬件内部, negedge移位)                             │
│  扫描链所有寄存器锁存配置值                                    │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 硬件使用                                                      │
│                                                              │
│  SCAN_CHAIN输出 → SCHEDULER (E,C,M,N,m,n,e,p,q,r,t)          │
│                → PROCESSING (H,W,R,S,E,F,C,M,N,U...)         │
│                → PE Array (enables + LN sels + NoC IDs)      │
│                                                              │
│  配置完成后scan_en=0, 硬件开始正常工作                         │
└─────────────────────────────────────────────────────────────┘
```

## 七、为什么我们tiny配置的参数是错的

1. 我们用 `gen_tiny_config.py` 生成tiny层配置（3644 bits）
2. 但我们实际上加载的是 `tiny/serial_data.txt` 这个**之前被覆盖为Conv1配置**的文件（10935 bytes）
3. 后来改用 `tiny_config_lf.txt`（从tiny/serial_data.txt转换换行符），但仍是Conv1配置
4. 同时 `config_script.py` 的**首bit重复bug**导致参数偏移
5. 结果: scan chain加载了错误的、偏移的参数

**修复方向**: 
- 修复config_script.py第170行的重复bug
- 用修复后的脚本重新生成tiny配置
- 或者直接用force绕过扫描链（调试用）
