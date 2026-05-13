# complete_version/ — 目录介绍

> 用途：所有 GitHub 原始项目的**完整只读备份**。不做任何修改，仅用于追溯和对比。

---

## 一级子目录

### `dldldlfma/`
**来源**: GitHub 用户 dldldlfma 的 eyeriss_v1 仓库
**内容**:
| 路径 | 说明 |
|------|------|
| `eyeriss_v1-master/Ccode_ref/` | C++ 参考代码 (main.cpp, pe.h, utils.h) + VS 工程文件 |
| `eyeriss_v1-master/verilog_code/ksg/` | ksg 的 Verilog: cnnip 控制器 + AXI 接口 + multicast_ctrl + pe + fifo |
| `eyeriss_v1-master/verilog_code/kdh/` | kdh 的 README（仅说明文档，无代码） |
| `eyeriss_v1-master/verilog_code/pcb/` | PCB 相关 README |
| `eyeriss_v1-master/eyeriss.pptx` | PPT 演示文稿 |

**评估**: ❌ **不可用**。ksg 部分只有 multicast_ctrl 和 PE 片段，不是完整加速器。Kdh 部分无实际代码。此项目严重不完整。

---

### `mmdnmz/`
**来源**: GitHub 用户 mmdnmz 的 Eyeriss 仓库
**内容**:
| 路径 | 说明 |
|------|------|
| `Eyeriss-main/src/` | 27 个 Verilog 文件：PE, PE_Cluster, PE_Controller, SPad, Buffer, Counter 等 |
| `Eyeriss-main/sim/` | PE_tb.sv + wave.do (ModelSim 波形脚本) |
| `Eyeriss-main/README.md` | 项目说明 |

**评估**: ❌ **不可用**。采用 PE_Cluster 结构（与论文的 12×14 PE Array 不同），更像是"受 Eyeriss 启发"的自有设计。无调度器、扫描链、GLB 等关键模块。

---

### `moateff/`
**来源**: GitHub 用户 moateff 的 4 个子项目（**最完整的作者系列**）

| 路径 | 日期 | 说明 |
|------|------|------|
| `2025_7_18_Eyeriss-v1-Data-Delivery-Pattarn-main/src/` | 2025-07-18 | P1: C 行为级模型 (7 文件) |
| `2025_7_23_Eyeriss-v1-Processing-Element-main/` | 2025-07-23 | P2: PE 独立 RTL + TB + 测试数据 |
| `2025_8_23_Eyeriss-v1-Network-on-Chip-main/` | 2025-08-23 | P3: NoC 独立 RTL (GIN+GON+FIFO) |
| `2025_11_1_Eyeriss-v1-main/` | 2025-11-01 | P4: **全系统集成版** |

#### P1 文件清单 (`2025_7_18_.../src/`)
| 文件 | 用途 |
|------|------|
| `run.c` | 主程序，协调各模块 |
| `Scheduler.c` | 3 层嵌套循环调度器 |
| `Array.c` | 4D 连续内存分配器 |
| `ifmap_index_generator.c` | Ifmap 地址序列生成 |
| `filter_index_generator.c` | Filter 地址序列生成（含 lock-step） |
| `psum_index_generator.c` | Psum 地址序列生成（含 lock-step） |
| `parameter.txt` | 测试参数配置 |

#### P2 文件清单 (`2025_7_23_.../`)
| 路径 | 说明 |
|------|------|
| `src/pe.v` | PE 顶层 |
| `src/pe_ctrl.sv` | 6 状态 PE 控制器 |
| `src/pe_wrapper.v` | PE 封装器 |
| `src/ifmap_spad.v` | Ifmap Scratchpad (12深度) |
| `src/filter_spad.v` | Filter Scratchpad (224深度) |
| `src/psum_spad.v` | Psum Scratchpad (24深度) |
| `src/signed_seq_multiplier.v` | 有符号序列乘法器 |
| `src/wallace_tree_multiplier.v` | Wallace Tree 乘法器 |
| `src/truncator.v` | 32→16 bit 截断器 |
| `src/zero_skipping.v` | 零值跳过逻辑 |
| `src/carry_lookahead_adder.v` | 超前进位加法器 |
| `src/clk_gating.v` | 时钟门控 |
| `src/dff.v`, `dff_en.v` | 触发器和使能触发器 |
| `src/fifo_*.v` (6文件) | FIFO 实现系列 |
| `src/mux2x1.v` | 2:1 多路选择器 |
| `sim/PE_tb.sv` | PE 测试平台 |
| `sw/*.c` | C 软件工具 (数据生成/转换) |
| `.mem/conv1~5/` | 5 组卷积测试向量 (.mem) |
| `.mem/example1~3/` | 3 组简单测试向量 |
| `.png/` | 仿真结果截图 |

#### P3 文件清单 (`2025_8_23_.../`)
| 路径 | 说明 |
|------|------|
| `src/gin.sv` | GIN 顶层 |
| `src/gin_mcc.sv` | GIN 多播控制器 (tag 匹配) |
| `src/gin_xbus.sv` | GIN 交叉开关 |
| `src/gin_fifo.sv` | GIN FIFO 封装 |
| `src/gon.sv` | GON 顶层 |
| `src/gon_mcc.sv` | GON 多播控制器 |
| `src/gon_xbus.sv` | GON 交叉开关 |
| `src/gon_fifo.sv` | GON FIFO 封装 |
| `src/fifo_*.v` (4文件) | FIFO 基础组件 |
| `run.sh` | 仿真运行脚本 |

#### P4 文件清单 (`2025_11_1_.../`)
见 `../moateff/introduce_file.md`（与 takeover/moateff 目录内容相同）。

---

### `theniloufar/`
**来源**: GitHub 用户 theniloufar 的 eyeriss-inspired-PE
**内容**: PE 级别的教学项目 + Circular Buffer 实现
**评估**: ❌ **不可用**。仅有 PE，无完整加速器。

---

## 使用说明
- **不要修改此目录下任何文件** — 这是原始作者的代码快照
- 需要运行原始代码时，复制到 `H:/moateff_test/` 或新目录
- 对比验证时，以此目录为"原始参考"
