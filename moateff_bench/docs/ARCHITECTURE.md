# Eyeriss v1 硬件架构文档

## 1. 顶层模块层次

```
eyeriss (EYERISS.sv)
├── SCHEDULER (scheduler.sv)
│   └── 9状态FSM: IDLE→CHECK→OUTER_LOOP→INNER_LOOP→START_PASS→PROCESS→PASS_DONE→DUMPING→DONE
│       嵌套循环: for N; for C; for M; (3级tiling)
│       输出: filter_ids, channel_ids, ifmap_ids (ID范围)
│
├── PROCESSING (processing_unit.sv)
│   ├── pe_array (pe_array.sv)
│   │   ├── PE[0..11][0..13] × 168 (pe_wrapper.v → pe.v)
│   │   │   每PE: ifmap_spad(12深) + filter_spad(224深) + psum_spad(24深)
│   │   │   MAC: 16×16→32, truncate→16, accumulate
│   │   │   PSum垂直流动: PE[row+1].opsum → PE[row].ipsum
│   │   ├── ifmap_gin (gin_wrapper)
│   │   ├── filter_gin (gin_wrapper)
│   │   ├── ipsum_gin (gin_wrapper)
│   │   └── opsum_gon (gon_wrapper)
│   │
│   └── noc_wrapper (noc_wrapper.sv)
│       ├── pass_controller (4状态: IDLE→START→PROCESSING→DONE)
│       └── noc_controller
│           ├── ifmap_noc_controller (index_generator + mapper + tag_generator + fifo)
│           ├── filter_noc_controller
│           ├── ipsum_noc_controller
│           └── opsum_noc_controller
│
├── GLB (glb_unit.sv)
│   ├── U1_IFMAP (ifmap_glb.sv) — 4-bank BRAM, 7945深度
│   ├── U2_FILTER (filter_glb.sv) — 4-bank BRAM, 3872深度
│   ├── U3_BIAS (bias_glb.sv) — 4-bank BRAM, 64深度
│   └── U4_PSUM (psum_glb.sv) — 4-bank BRAM, 46656深度
│
├── INTF (interface_unit.sv)
│   └── async_fifo (跨时钟域 core_clk↔link_clk)
│
├── ReLU (relu_array.sv)
│   └── relu[0..3] — 4路并行
│
└── SCAN_CHAIN (scan_chain.sv)
    └── 17参数寄存器 + PE使能矩阵 + NoC路由ID (可串行配置)
```

## 2. 模块功能定义

### 2.1 Scheduler (调度器)

**文件**: `src/scheduler.sv`

**功能**: 生成嵌套循环的 pass 描述，控制整个卷积计算的执行顺序。

**状态机**:
```
IDLE ──(start)──→ CHECK ──(start_pass)──→ START_PASS
                    ↑                            ↓
                    │                        PROCESS (busy=1)
                    │                            ↓ (noc_done)
                    │                        PASS_DONE
                    │                            ↓
                    ├────────────── INNER_LOOP ←─┘
                    │                  ↓
                    │              DUMPING (ofmap_dump=1)
                    │                  ↓ (dump_done)
                    └────────── OUTER_LOOP ←─────┘
                                       ↓
                                      DONE
```

**循环结构** (C模型验证):
```c
for (N_ind = 0; N_ind < N; N_ind += n)
  for (C_ind = 0; C_ind < C; C_ind += q*r)
    for (M_ind = 0; M_ind < M; M_ind += p*t)
      pass(filter_start=M_ind, channel_start=C_ind, ifmap_start=N_ind)
```

**接口**:
| 端口 | 方向 | 位宽 | 说明 |
|------|------|------|------|
| clk, reset | input | 1 | 时钟与复位 |
| start | input | 1 | 启动整个卷积 |
| busy | output | 1 | 正在处理 |
| done | output | 1 | 全部完成 |
| start_pass | input | 1 | 触发一个pass |
| pass_done | output | 1 | 当前pass完成 |
| start_noc | output | 1 | 启动NoC |
| noc_done | input | 1 | NoC处理完成 |
| ofmap_dump | output | 1 | 请求输出写回 |
| dump_done | input | 1 | 写回完成 |
| E,C,M,N | input | 6-10 | 层维度参数 |
| m,n,e,p,q,r,t | input | 2-8 | 映射参数 |
| filter_ids[0:1] | output | 10 | 滤波器ID范围 |
| ifmap_ids[0:1] | output | 3 | 输入图ID范围 |
| channel_ids[0:1] | output | 10 | 通道ID范围 |

### 2.2 Processing Unit (处理单元)

**文件**: `src/PE Array/processing_unit.sv`

**功能**: PE阵列 + NoC控制器，执行实际卷积计算。

### 2.3 PE Array

**文件**: `src/PE Array/Processing Element/pe_array.sv`

**规模**: 12行 × 14列 = 168 PE

**数据流**:
- IFMAP: GIN → 行广播 → 各PE ifmap FIFO
- FILTER: GIN → 列广播 → 各PE filter FIFO
- IPSUM: GIN或下方PE → PE ipsum FIFO
- OPSUM: PE → 上方PE或GON

**PSum垂直流动**:
```
PE[row+1][col].opsum → PE[row][col].ipsum
```
- ipsum_ln_sel[row]=1: 从GIN取ipsum (列底)
- ipsum_ln_sel[row]=0: 从PE[row+1]取ipsum
- opsum_ln_sel[row]=1: 输出到GON (列顶)
- opsum_ln_sel[row]=0: 输出到PE[row-1]

### 2.4 PE (处理单元)

**文件**: `src/PE Array/Processing Element/pe.v`

**数据精度**: Q3.13 定点 (16-bit有符号, step=1/8192)

**SPAD**:
- ifmap_spad: 12深 × 16-bit (移位寄存器)
- filter_spad: 224深 × 16-bit (BRAM)
- psum_spad: 24深 × 16-bit (BRAM)

**MAC数据路径**:
```
ifmap_spad[addr] ──→ [×] ←── filter_spad[addr]
                       ↓ (32-bit)
                  truncator (sel[15:0])
                       ↓ (16-bit)
                  [mux: acc/new] ←── ipsum_pixel
                       ↓
                  [+]
                       ↓
                  psum_spad[addr]
```

**PE控制器状态** (pe_controller.sv):
```
IDLE → PROCESS → ACCUMULATE → STRIDE → PADDING → LOAD → IDLE
```
- PROCESS: 迭代 S×q 行 × p 列
- ACCUMULATE: 累加部分和
- STRIDE: 移位ifmap SPAD
- PADDING: 边界填充

### 2.5 NoC (片上网络)

**GIN (Global Input Network)**: 两级组播
- Row MCC: 行标签匹配
- Column XBus + MCC: 列标签匹配
- 只有当 {row_tag, col_tag} 匹配PE的配置ID时，数据才被接收

**GON (Global Output Network)**: 两级汇聚
- Column XBus: 列内收集
- Row MCC: 行选择
- 带标签的输出数据路由到GLB

**NoC控制器**:
- pass_controller: 顺序启动4个NoC通道
- ifmap_noc_controller: ifmap地址生成 + 标签生成
- filter_noc_controller: filter地址生成 + 标签生成
- ipsum_noc_controller: 输入psum地址生成
- opsum_noc_controller: 输出psum地址生成

### 2.6 Index Generator (地址生成器)

**ifmap_index_generator** 循环结构:
```
for n_ind in 0..n-1:
  for W_ind in 0..W-1:
    for q_ind in 0..q-1:
      for H_ind in 0..D-1:  (D = e + R - U)
        for r_ind in 0..r-1:
          output: (ifmap_idx, channel_idx, row_idx, col_idx)
```

**filter_index_generator**: lock-step counter 机制
- 内层: p→q→S 子迭代 (每次4个地址)
- 外层: R→r→t 循环

**psum_index_generator**: lock-step counter 机制
- 内层: p→F→n 子迭代
- 外层: E→t 循环

### 2.7 Mapper (地址映射)

**文件**: `src/PE Array/Network on Chip/Network on Chip Controller/mapper.sv`

**公式**: `addr = idx4×(dim3×dim2×dim1) + idx3×(dim2×dim1) + idx2×dim1 + idx1`

**IFMAP**: addr = n×(C×H×W) + c×(H×W) + h×W + w
**FILTER**: addr = m×(C×R×S) + c×(R×S) + r×S + s
**PSUM**: addr = n×(M×F×E) + m×(F×E) + f×E + e

### 2.8 GLB (全局缓存)

**文件**: `src/GLB UNIT/glb_unit.sv`

**结构**: 4组独立双端口BRAM
- Port A: 64-bit写 (4 bank并行)
- Port B: 16-bit读 (bank选择)

**深度**:
- IFMAP: 7945 (每个bank ~1986)
- FILTER: 3872 (每个bank ~968)
- BIAS: 64 (每个bank ~16)
- PSUM: 46656 (每个bank ~11664)

### 2.9 Interface Unit (接口单元)

**文件**: `src/INTERFACE UNIT/interface_unit.sv`

**功能**: 跨时钟域数据传输 (core_clk ↔ link_clk)
- Forward: DRAM → IFMAP/FILTER/BIAS GLB
- Backward: PSUM GLB → ReLU → DRAM
- 使用异步FIFO (Gray码指针)

### 2.10 Scan Chain (配置链)

**文件**: `src/SCAN CHAIN/scan_chain.sv`

**寄存器顺序**: H, W, R, S, E, F, C, M, N, U, m, n, e, p, q, r, t
**位宽合计**: 92 bits (参数) + 3552 bits (PE阵列配置) = 3644 bits (tiny层)
**加载方式**: scan_en=1时每个时钟周期移入1 bit

## 3. 主要信号时序

### 3.1 Scheduler 启动时序
```
clk:     ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐
         ┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘
start:   ────┐     ┌──────────────
             └─────┘
busy:    ──────────┐          ┌───
                   └──────────┘
start_pass: ──────────────┐
                          └──────────
```

### 3.2 PE MAC 流水线 (5级)
```
Cycle:   T0    T1    T2    T3    T4
ifmap:  [RD]→[─]→[─]→[─]→[─]
filter: [RD]→[─]→[─]→[─]→[─]
mult:         [×]→[×]→[×]→[─]
trunc:              [T]→[─]→[─]
accum:                   [+]→[WR]
```

## 4. 与Eyeriss论文的对应

| 论文描述 | RTL实现 | 状态 |
|----------|---------|------|
| 12×14 PE阵列 | pe_array.sv 168 PE | ✅ |
| Row-Stationary数据流 | PSum垂直流动 + 数据广播 | ✅ |
| 两级NoC (GIN/GON) | gin/gon + mcc/xbus | ✅ |
| 全局缓存 (GLB) | 4×双端口BRAM | ✅ |
| 可配置调度器 | scheduler.sv 9状态FSM | ✅ |
| Scan chain配置 | scan_chain.sv 串行加载 | ✅ |
| ReLU激活 | relu_array.sv | ✅ |
| 时钟门控 | pe_clk_gating.v | ✅ |
| 零跳过 | pe_zero_skipping.v | ✅ |
