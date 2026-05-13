# Eyeriss v1 代码学习指南

> 使用方法：对照阅读每个RTL文件时，先读本指南对应章节理解设计意图，再读代码。
> 标注 `[关键]` 的模块是毕设核心，必须掌握。

---

## 1. 顶层集成 — `rtl/EYERISS.sv`

**作用**: 将所有子模块连接成完整加速器。

**例化顺序**（也是数据流向）:
```
SCAN_CHAIN → SCHEDULER → PROCESSING(pe_array + noc_wrapper) → GLB → INTF → ReLU
```

**关键连线**（读代码时关注这些信号）:
- `SCHEDULER.noc_done ← PROCESSING.done` — 调度器等处理单元完成
- `SCHEDULER.start_noc → PROCESSING.start` — 调度器启动处理
- `SCHEDULER.filter_ids → 输出到顶层` — ID范围给外部参考
- `PROCESSING.ifmap_re_from_glb → GLB.re_b_ifmap` — NoC读GLB
- `GLB.rdata_b_ifmap → PROCESSING.ifmap_from_glb` — GLB返回数据

**学习要点**: 
- 这是硬件集成视图，看懂连线就能理解数据流
- 大量参数传递（`#(.XXX)`），每一组参数控制一个子模块的规模

---

## 2. 调度器 — `rtl/scheduler.sv` [关键]

**作用**: 毕设核心模块。将卷积循环（N→C→M）分解为一系列 pass，每个 pass 处理一个数据块。

**状态机** (9状态):
```
IDLE → CHECK → START_PASS → PROCESS → PASS_DONE → INNER_LOOP → DUMPING → OUTER_LOOP → DONE
```

**嵌套循环逻辑**（代码阅读顺序）:
1. `always_comb` 块 (行97-177): 决定下一状态 `state_nxt`
2. `always_ff` 块 (行65-81): 在 posedge 更新当前状态
3. 第二个 `always_comb` 块 (行180-199): 根据状态生成输出ID

**关键循环变量**:
- `M_crnt`: 当前输出通道位置（步进 m）
- `C_crnt`: 当前输入通道位置（步进 q*r）
- `m_crnt`: pass内滤波器子块位置（步进 p*t）
- `E_crnt`: 当前OFM行位置（步进 e）

**OUTER_LOOP 逻辑** (行127-147):
```
M_crnt += m  →  if M_crnt >= M: reset M, E_crnt += e  →  if E_crnt >= E: reset E, N_crnt += n
```
理解：先遍历完所有输出通道，再推进输出行，最后推进batch。

**INNER_LOOP 逻辑** (行110-124):
```
m_crnt += p*t  →  if m_crnt >= m: reset m, C_crnt += q*r
```
理解：pass内遍历滤波器块，然后推进通道块。

**学习要点**:
- 这个模块实现了RS数据流的核心调度逻辑
- 理解 `p, q, r, t` 四个映射参数如何决定PE阵列的并行度

---

## 3. PE核心 — `rtl/pe.v` [关键]

**作用**: 单个处理单元。执行 ifmap行 ⊗ filter行 的1D卷积。

**内部结构**（按例化顺序）:
```
zero_skipping → ifmap_spad(12深) → filter_spad(224深) → psum_spad(24深)
  → multiplier(16×16→32) → truncator(32→16) → adder → 输出
```

**数据路径**（行155-197，读代码时追踪这些wire）:
1. `ifmap_from_spad` × `filter_from_spad` → `mul_result` (32-bit)
2. `truncated_result` = mul_result的低16位
3. `mux3`: 选择 `truncated_result`（新MAC）或 `ipsum_pixel`（累加外部psum）
4. `adder`: `mux1_out_r` + `mux3_out`
5. 结果写入 `psum_spad` 或通过 `push_opsum` 送出

**SPAD读写逻辑**:
- ifmap_spad: 移位寄存器式，每次 STRIIDE 时移位 U*q 个位置
- filter_spad: BRAM式，按地址索引
- psum_spad: BRAM式，支持前向旁路（forward=1时跳过读，直接用上次结果）

**学习要点**:
- PE做的是1D行卷积，不是2D
- Q3.13定点MAC: `(a×b)>>13` 累加
- forward旁路是加速连续同地址psum累加的关键优化

---

## 4. PE控制器 — `rtl/pe_controller.sv` [关键]

**作用**: 控制PE的6状态执行流程。

**6个状态**:
| 状态 | 做什么 | 持续周期 |
|------|--------|---------|
| IDLE | 等待SPAD就绪 | - |
| PROCESS | MAC循环: ifmap[i]×filter[i×p+j] | S×q 行 × p 列 |
| ACCUMULATE | 加下方PE来的psum | p 周期 |
| STRIDE | 移位ifmap_spad | U×q 周期 |
| PADDING | 边界补零 | V 周期 |
| LOAD | 重置ifmap_spad | n 迭代 |

**关键控制信号**:
- `reset_accumulation`: 新filter行开始时清零累加器
- `accumulate_ipsum`: 选择外部psum输入（而非本地MAC结果）
- `shift`: 触发ifmap_spad移位
- `wr_psum`: 写psum_spad使能

**学习要点**:
- 控制器用 `negedge clk`，数据路径用 `posedge`（半周期偏移设计）
- 理解 PROCESS→ACCUMULATE→STRIDE 的循环就是RS数据流的PE级实现

---

## 5. PE阵列 — `rtl/pe_array.sv`

**作用**: 12×14 PE阵列 + GIN/GON 集成。

**PSum垂直流动**（核心连通方式，行211-217）:
```systemverilog
// 每个PE的ipsum来源：要么从GIN（列底），要么从下方PE
.ipsum(ipsum_ln_sel[i] ? ipsum_from_gin[i] : opsum_from_pe[i+1])

// 每个PE的opsum去向：要么到GON（列顶），要么到上方PE
.pop_opsum(opsum_ln_sel[i] ? pop_opsum_to_gon[i] : (~opsum_empty[i] & ~ipsum_full[i-1]))
```

**扫描链配置**（每个PE行需要配置）:
- `enable`: 是否使能 (1 bit × 14列)
- `ipsum_ln_sel`: PSum输入选择 (1 bit × 14列)
- `opsum_ln_sel`: PSum输出选择 (1 bit × 14列)
- `ifmap_gin_id`: ifmap GIN 标签 (4+14×5 bits)
- `filter_gin_id`: filter GIN 标签 (15×4 bits)
- `ipsum_gin_id`: ipsum GIN 标签 (15×4 bits)
- `opsum_gon_id`: opsum GON 标签 (15×4 bits)

**学习要点**:
- 12行×14列是物理规模，实际使用多少通过 enable 配置
- psum流动方向是↑（下方→上方），因为底部PE先接收到数据
- 配置链的总位数决定了 serial_data.txt 的长度

---

## 6. NoC控制器 — `rtl/noc_controller.sv` + `rtl/noc_wrapper.sv`

**作用**: 管理4路NoC通道（ifmap/filter/ipsum/opsum）的并行执行。

**pass_controller 状态** (4状态):
```
IDLE → START_NOCS → PROCESSING（等4路完成）→ DONE
```

**4路NoC通道**:
1. `ifmap_noc_controller`: 生成ifmap地址和标签
2. `filter_noc_controller`: 生成filter地址和标签
3. `ipsum_noc_controller`: 生成输入psum地址和标签
4. `opsum_noc_controller`: 生成输出psum地址和标签

**每路NoC的内部结构**:
```
IndexGenerator → Mapper(4D→1D) → SyncFIFO → TagGenerator
                                        ↓
                                   GLB_read/write
```

**学习要点**:
- 4路并行执行，但 pass_controller 等最慢的一路完成
- D = e + R - U 是ifmap tile高度（考虑了filter overhead）

---

## 7. 地址生成器 — `rtl/ifmap_index_generator.sv` 等 [关键]

### 7.1 Ifmap Index Generator

**5层嵌套循环** (从外到内):
```
for n_ind:      batch内的ifmap索引
  for W_ind:    ifmap列
    for q_ind:  通道组
      for D_ind: tile内行 (D = e+R-U)
        for r_ind: 行组
```

**输出**: `(ifmap_index, channel_index, row_index, col_index)`

### 7.2 Filter Index Generator

**lock-step计数器机制**:
- 内层: 4次迭代推进 (p, q, S) 联合索引
- 外层: 循环 (R, r, t)
- 锁存机制 (`p_reg, q_reg, S_reg`): 保存上一次停止的位置，下轮从那里继续

### 7.3 PSum Index Generator

- 与filter类似，但维度是 (p, F, n) 而非 (p, q, S)
- `channel_index = channel_start + p_ind + t_ind * p` 对应滤波器索引

**学习要点**:
- lock-step机制是为了4个一组批量生成地址（匹配GLB的64-bit位宽）
- 索引生成公式直接对应论文中的RS数据流映射

---

## 8. Mapper — `rtl/mapper.sv`

**作用**: 将4D坐标转为GLB线性地址。

**唯一公式**:
```
addr = idx4 × (dim3 × dim2 × dim1) + idx3 × (dim2 × dim1) + idx2 × dim1 + idx1
```

**不同数据类型的dim配置**:
| 数据类型 | dim4 | dim3 | dim2 | dim1 |
|----------|------|------|------|------|
| IFMAP | N | C | H | W |
| FILTER | M | C | R | S |
| PSUM | N | M | F | E |
| BIAS | - | - | - | M (1D) |

**学习要点**:
- 纯组合逻辑，不消耗时钟周期
- 行优先（row-major）存储格式

---

## 9. GIN/GON — `rtl/gin.sv`, `rtl/gon.sv`

### GIN (Global Input Network) — 组播
```
GIN_Wrapper → gin.sv:
  Row MCC: 比较 row_tag，匹配的行通过
    → Column XBus + MCC: 比较 col_tag，匹配的列接收数据
```

### GON (Global Output Network) — 汇聚
```
gon.sv → GON_Wrapper:
  Column XBus: 列内汇聚
    → Row MCC: 行选择，匹配的输出到GLB
```

**标签匹配逻辑**: 每个PE有配置的 `{row_id, col_id}`。当GIN广播 `{row_tag, col_tag}` 时，ID匹配的PE接收。

**学习要点**:
- 标签值15（4-bit）或31（5-bit）表示"禁用"
- 这是实现"数据只送到需要的PE"的关键机制

---

## 10. GLB — `rtl/glb_unit.sv` + `rtl/*_glb.sv`

**4个独立Buffer**:

| Buffer | 深度(总) | 每bank深度 | 用途 |
|--------|----------|-----------|------|
| IFMAP | 7945 | ~1986 | 输入特征图 |
| FILTER | 3872 | ~968 | 卷积核权重 |
| BIAS | 64 | ~16 | 偏置 |
| PSUM | 46656 | ~11664 | 部分和/输出 |

**双端口BRAM**:
- Port A: 64-bit写（4 bank并行）
- Port B: 16-bit读（bank选择 = addr[1:0]）

**学习要点**:
- GLB是filter/in/out数据的中间缓存，不是全量存储
- 深度按AlexNet Conv1分块需求设计
- negedge clk操作（与posedge系统形成半周期偏移）

---

## 11. Scan Chain — `rtl/scan_chain.sv`

**作用**: 串行配置所有寄存器（参数 + PE阵列设置）。

**寄存器顺序**: H→W→R→S→E→F→C→M→N→U→m→n→e→p→q→r→t → PE阵列配置

**配置方法**: scan_en=1, 每个时钟周期 scan_in 移入1 bit

**学习要点**:
- 这是静态配置，在计算开始前完成
- 实现了论文中"离线配置"的概念
- PE阵列配置（enables/IDs）占3644bits中的3552bits

---

## 12. Python行为模型 — `py/eyeriss_model.py` [关键]

**与RTL一一对应**:

| Python类 | 对应RTL | 说明 |
|----------|---------|------|
| `LayerConfig` | scan chain寄存器 | 层参数+映射参数 |
| `Scheduler.generate_passes()` | scheduler.sv | 循环生成pass描述 |
| `IndexGenerators` | *_index_generator.sv | 地址序列生成 |
| `GLB` | glb_unit.sv | 4-bank存储器模型 |
| `EyerissModel.compute_golden()` | PE阵列 | Q3.13卷积计算 |

**用途**:
1. 快速验证RTL输出正确性（golden reference）
2. 理解地址生成规律
3. 调试配置参数

---

## 学习路线建议

**第一周**: 理解架构
1. 读 `docs/ARCHITECTURE.md` → 理解模块层次
2. 读 `rtl/scheduler.sv` → 理解嵌套循环（毕设核心）
3. 读 `rtl/pe.v` → 理解PE数据路径

**第二周**: 理解数据流
4. 读 `rtl/pe_array.sv` → 理解PSum垂直流动
5. 读 `rtl/ifmap_index_generator.sv` → 理解地址生成
6. 运行 `py/eyeriss_model.py` → 观察地址序列

**第三周**: 系统集成
7. 读 `rtl/EYERISS.sv` → 理解顶层连线
8. 读 `rtl/noc_controller.sv` → 理解NoC调度
9. 编译运行仿真 → 观察波形
