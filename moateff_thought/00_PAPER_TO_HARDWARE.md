# Eyeriss论文到硬件实现对照分析

> 本文档对应JSSC 2017 ("Eyeriss: An Energy-Efficient Reconfigurable Accelerator for Deep CNNs") 和 ISCA 2016 ("Eyeriss: A Spatial Architecture for Energy-Efficient Dataflow for CNNs") 论文，逐一对照RTL实现。
> 
> 论文PDF路径: H:/complete_version/moateff/2025_11_1_Eyeriss-v1-main/docs/
> RTL路径: H:/moateff_test/src/

---

## 一、论文架构总览 vs RTL顶层

### 论文 Fig.4 — Eyeriss系统架构

论文描述的系统包括:
- 168 PE (12行×14列)
- GLB (Global Buffer): 108 KB, 25+2 banks
- NoC: GIN (Global Input Network) + GON (Global Output Network)
- RLC CODEC (Run-Length Compression)
- ReLU
- 顶层控制器 (Top-level Control) + 链路时钟域 (Link Clock Domain)

### RTL对应

| 论文章节 | 论文描述 | RTL模块 | 文件 |
|----------|---------|---------|------|
| IV-A: PE Array | 168 PEs, 12×14 | PE Array | src/PE Array/ |
| IV-B: GLB | 108KB, 25+2 banks | GLB Unit | src/GLB UNIT/ |
| IV-C: NoC | GIN + GON, X-Bus + MCC | NoC | src/PE Array/Network on Chip/ |
| IV-D: RLC | Run-Length CODEC | **未实现** | — |
| IV-E: ReLU | ReLU activation | ReLU | src/RelU/ |
| V-A: Top Control | 两层控制 | Scheduler + Pass Controller | src/scheduler.sv + src/.../pass_controller.sv |
| V-B: Clocking | 双时钟域: link_clk + core_clk | Interface Unit | src/INTERFACE UNIT/ |
| V-C: Scan Chain | 串行配置 | Scan Chain | src/SCAN CHAIN/ |

---

## 二、RS数据流 — 论文 Section III vs RTL Scheduler

### 论文描述

论文Section III-B描述RS数据流的核心思想:

1. **1D行卷积在PE内**: 每个PE处理一个filter行×一个ifmap行的1D卷积
2. **PE Set**: 一组PE并行处理不同的filter行 (R个PE行) 和不同的ifmap行 (E个PE列)
3. **PSum垂直流动**: 自下而上累加部分和
4. **多维复用**: 同时最大化卷积复用、滤波器复用、输入复用

### RTL实现

**Scheduler (scheduler.sv)** 实现了将7层卷积循环映射到PE阵列的调度:

```
论文7层循环: for N; for M; for E; for F; for C; for R; for S

RTL调度分解:
  for N_ind (step n):    → Scheduler OUTER_LOOP (N_crnt)
    for C_ind (step q*r): → Scheduler INNER_LOOP (C_crnt)  
      for M_ind (step p*t):
        → 一个PASS
        → NoC Index Generator展开 R,S 循环
        → PE Controller执行 1D 卷积
```

**映射参数** (scan chain配置):
| 参数 | 含义 | 论文对应 |
|------|------|----------|
| p | 水平PE并行度 | PE set的filter列数 |
| q | 通道并行度 | 每个PE处理的通道数 |
| r | 通道组数 | 通道维度的PE并行度 |
| t | 滤波器组数 | 滤波器维度的PE并行度 |
| e | OFM tile高度 | 一次处理的行数 |
| m | 滤波器m子块 | pass间psum积累的粒度 |

---

## 三、PE阵列 — 论文 Section IV-A vs RTL

### 论文描述
- 12行×14列 = 168 PE
- 每个PE: 3个SPAD (ifmap/filter/psum)
- 数据通过GIN多播到达PE，通过GON汇聚离开PE
- PE间PSum垂直流动

### RTL实现

**PE (pe.v)** — 对应论文 Fig.9 PE数据路径:

论文描述的PE包含:
- 乘法器 → 加法器 → 截位器
- 3个SPAD: ifmap(12深), filter(224深), psum(24深)
- 零跳过逻辑 (论文 Section V-E)

RTL实现:
```
ifmap_spad(12深, 移位寄存器式) × filter_spad(224深, BRAM式)
  → multiplier (16×16→32)    [pe_multiplier.v]
  → truncator (32→16)         [pe_truncator.v]
  → mux → adder               [pe_adder.v]
  → psum_spad(24深, BRAM式)
```

**PSum垂直流动** — 对应论文 Fig.7 / Fig.8:

论文描述: "The psums move vertically from the bottom row all the way up to the top row of the PE array"

RTL实现 (pe_array.sv):
- ipsum_ln_sel[row]=1: 底部PE从GIN接收初始psum
- ipsum_ln_sel[row]=0: PE从PE[row+1]接收psum
- opsum_ln_sel[row]=1: 顶部PE输出到GON
- opsum_ln_sel[row]=0: PE输出到PE[row-1]

---

## 四、GLB — 论文 Section IV-B vs RTL

### 论文描述 (JSSC 2017, Section IV-B):

"The GLB is 108 kB and contains 25 banks of 512×64-bit SRAMs... Each bank is assigned entirely to ifmaps or psums, and the assignment is reconfigurable... The remaining 8 kB (two banks) is allocated for filter weights."

### RTL实现差异

论文: 25个独立bank, 每个512×64-bit = 4KB, 可动态分配给ifmap或psum
RTL: 4个独立的GLB实例 (ifmap/filter/bias/psum)，每个内部4-bank

**差异分析**:
- 论文的25-bank设计是为了"可重构ifmap/psum分配比例"
- RTL简化为固定分配: IFMAP_GLB + PSUM_GLB 替代了论文的25个可重构bank
- 这种简化使设计复杂度大幅降低，但丧失了跨层灵活配置不同ifmap/psum比例的能力
- FILTER_GLB (8KB = 2 banks × 4KB) 与论文的2个filter bank一致

**详见** H:/moateff_QaR/Q3_GLB_Banks.md

---

## 五、NoC — 论文 Section IV-C vs RTL

### 论文描述

GIN: 两级多播网络
- 第一级: "X-Bus" (水平) — 每行分发
- 第二级: "MCC" (Multicast Controller) — 列选择

GON: 两级汇聚网络
- "The GON is similar to the GIN in structure but used for reading psums"

### RTL实现

RTL NoC比论文描述更详细，分为:

**GIN层级** (gin.sv, gin_mcc.sv, gin_xbus.sv):
```
GIN_Wrapper → Row MCC (行标签匹配)
  → 匹配的行: X-Bus分发到各列
  → Column MCC (列标签匹配): 接收数据
```

**GON层级** (gon.sv, gon_mcc.sv, gon_xbus.sv):
```
GON_Wrapper ← Row MCC (行选择)
  ← X-Bus汇聚各列
  ← Column MCC (列匹配)
```

**NoC控制器** — 论文未详细描述但在RTL中实现:
- 4路独立NoC通道 (ifmap/filter/ipsum/opsum)
- 每路含: Index Generator + Mapper + Tag Generator
- Pass Controller管理4路并行执行

**标签路由** — 论文提到的"PE identification tags"在RTL中的实现:
- NoC Controller的Tag Generator生成(row_tag, col_tag)对
- PE的Scan Chain配置存储(row_id, col_id)
- 只有tag匹配的PE接收数据

---

## 六、配置系统 — 论文 Section V-C vs RTL

### 论文描述

"All 1794 configuration bits are loaded serially through the scan chain in less than 100 μs... The scan chain configures the PE array mapping and the NoC data delivery patterns."

### RTL实现 (scan_chain.sv)

配置寄存器 (按顺序):
```
H(8) → W(8) → R(4) → S(4~6) → E(6) → F(6) → C(10) → M(10) → N(3)
→ U(3) → m(8) → n(3) → e(8) → p(5) → q(3) → r(2) → t(3)
→ PE阵列配置 (enables + NoC IDs)
```

[PE阵列配置位详情 — 见H:/moateff_QaR/Q5_Scan_Chain.md]

---

## 七、RTL超越论文的设计细节

以下是RTL中实现但论文未详细描述的设计:

1. **Index Generator的lock-step计数器机制** — 论文只说"预计算地址"，RTL实现了精细的(p,q,S)联合索引lock-step机制

2. **PE Controller的6状态FSM** — 论文只说PE"computes 1D convolution"，RTL细化为IDLE→PROCESS→ACCUMULATE→STRIDE→PADDING→LOAD

3. **Forward Bypass** — 论文未提及，但RTL的pe.v中实现了psum_spad的前向旁路

4. **时钟门控 (Clock Gating)** — 论文Section V-D提到时钟门控，RTL的pe_clk_gating.v实现了基于使能信号的时钟关断

5. **半周期时钟设计** — 论文未提，但RTL使用了negedge为主沿+posedge为控制沿的设计

---

## 八、论文功能 vs RTL实现对照表

| 论文功能 | RTL实现状态 | 备注 |
|----------|------------|------|
| 168 PE (12×14) | ✅ 完全实现 | pe_array.sv |
| RS数据流 | ✅ 完全实现 | scheduler.sv + PE阵列 |
| GLB 108KB | ⚠️ 简化 | 固定分配替代可重构bank |
| GIN/GON NoC | ✅ 完全实现 | 两级标签路由 |
| Scan Chain | ✅ 完全实现 | 串行配置链 |
| ReLU | ✅ 完全实现 | 4路并行 |
| RLC CODEC | ❌ 未实现 | 运行长度压缩 |
| 时钟门控 | ✅ 实现 | pe_clk_gating.v |
| 零跳过 | ✅ 实现 | pe_zero_skipping.v |
| 双时钟域 | ✅ 实现 | Interface Unit |
| 外部DDR接口 | ⚠️ 部分 | Interface Unit存在但未验证 |

---

## 九、论文关键数据 (来自JSSC 2017 Table III)

### AlexNet各层参数 (batch N=4)

| 层 | R | C | M | H/W | E/F | U | filter stride |
|----|---|---|---|-----|-----|---|---------------|
| CONV1 | 11 | 3 | 96 | 227 | 55 | 4 | 4 |
| CONV2 | 5 | 48(2组) | 256 | 27 | 27 | 1 | - |
| CONV3 | 3 | 256 | 384 | 13 | 13 | 1 | - |
| CONV4 | 3 | 192 | 384 | 13 | 13 | 1 | - |
| CONV5 | 3 | 192 | 256 | 13 | 13 | 1 | - |

### 芯片实测结果 (65nm CMOS, 200MHz)
- 功耗: 278 mW @ 1V
- 吞吐: 34.7 fps (AlexNet, N=4) = 23.1 GMAC/s
- 能效: 83.1 GMACS/W (峰值166 GMACS/W @ 0.58V)
- DRAM访问: 0.0029 access/MAC (仅37.4次DRAM访问/输入像素)
- PE利用率: 88%

### 面积分布 (12.25 mm²)
- GLB + PE SPADs: ~2/3 总面积
- 乘法器+加法器(全部168 PE): 仅7.4%
- 数据移动能耗占比 > ALU计算能耗

## 十、JSSC 2017 Section V 实现细节对照

### V-A: GLB组织
- 论文: 108 kB = 25 bank × 4KB (ifmap/psum可重构) + 2 bank × 4KB (filter)
- RTL: 4个固定GLB (ifmap/filter/bias/psum), 每个4-bank
- **差异**: RTL将25个可重构bank简化为2个固定bank (IFMAP_GLB + PSUM_GLB)
- **影响**: 丧失跨层灵活分配ifmap/psum比例的能力

### V-B: NoC
- 论文: GIN (Y-bus 12行 + X-bus 14列/行), GON (反向), LN (列内垂直)
- RTL: GIN/GON完全实现, LN通过ipsum_ln_sel/opsum_ln_sel实现
- 论文: filter/psum GIN 64-bit, ifmap GIN 16-bit
- RTL: 一致

### V-C: PE架构 (Fig.12)
- 论文: FIFO + SPAD + 3级流水线MAC + 零跳过
- RTL: pe_wrapper.v(FIFO) + pe.v(SPAD+MAC+零跳过) 完全匹配
- 论文: p=24 max, q=4 max (S_min=3时)
- RTL: p=5-bit, q=3-bit 参数化

### V-D: 时钟门控
- RTL: pe_clk_gating.v 实现基于enable的时钟关断

### V-E: 数据门控 (零跳过)
- 论文: 12-bit Zero Buffer, 节省45% PE功耗
- RTL: pe_zero_skipping.v 完全实现

## 十一、RTL vs 论文缺失功能

| 论文功能 | RTL状态 |
|----------|---------|
| RLC CODEC (运行长度压缩) | ❌ 完全未实现 |
| GLB 25-bank可重构 | ⚠️ 简化为4固定GLB |
| 外部DRAM控制器 | ⚠️ Interface Unit存在但数据加载未完成 |
| 离线mapper工具 | ⚠️ 有C模型(index_generator.c)但无完整mapper |

---

*参考论文*:
- eyeriss_jssc_2017.pdf — 完整的芯片实现论文 (12页)
- eyeriss_isca_2016.pdf — 架构与能效分析论文 (13页)  
- 2017_pieee_dnn.pdf — DNN处理综述 (35页, Section V-B涵盖Eyeriss)
