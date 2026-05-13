# moateff_bench/ — 目录介绍

> 用途：**整理后的干净交付物** — 毕业论文的主要产出目录。包含 RTL（原始+注释）、Python 行为模型、文档、测试平台、论文。

---

## 一级目录与文件

### `rtl/`
原始 RTL 代码（从 P4 复制，**未修改**），共 71 个文件。
目录结构与 `moateff/2025_11_1_.../src/` 完全相同。
| 子目录 | 内容 |
|--------|------|
| `EYERISS.sv` | 顶层模块 |
| `scheduler.sv` | 9 状态调度器 |
| `GLB UNIT/` | 7 文件: glb_unit, ifmap/filter/bias/psum_glb, dual_bram, glb_flop |
| `PE Array/` | PE 阵列 + NoC + Sync FIFO (~30 文件) |
| `RelU/` | 2 文件: relu_array, relu |
| `SCAN CHAIN/` | 3 文件: scan_chain, scan_ff, scan_ff_Nbit |
| `INTERFACE UNIT/` | 12 文件: interface_unit + async_fifo 系列 + mux/demux |

---

### `rtl_annotated/`
**RTL 注释版** — 每个 RTL 文件添加中文注释，解释关键信号和逻辑。
共 71 个注释文件 + 1 个框图文档。
| 文件 | 说明 |
|------|------|
| `00_BLOCK_DIAGRAM.md` | **7 张 ASCII art 架构图**：系统顶层、数据流、PE 内部、FSM 状态图、NoC 结构、psum 流、模块树 |
| `*.sv` / `*.v` | 对应的注释版 RTL 源码 |

注释版适合快速理解硬件设计，比读原始代码效率高 3-5 倍。

---

### `docs/`
项目文档集合。
| 文件 | 说明 |
|------|------|
| `ARCHITECTURE.md` | 硬件架构全面说明：模块层次、数据流、信号连接、参数系统 |
| `BEHAVIORAL_MODEL.md` | Python 行为模型说明：Q3.13 算术、conv/pool/relu 实现 |
| `STUDY_GUIDE.md` | **代码学习指南**：从零开始的 RTL 阅读顺序，从顶层到底层 |
| `CLOCK_EDGE_ANALYSIS.md` | 416 行深度分析：证明 negedge 为主是有意设计（88%模块），Scheduler 用 posedge 创造半周期时序分离 |
| `FILE_GUIDE.md` | 所有文件索引 |
| `PROGRESS.md` | 工作进度记录 |
| `README.md` | 项目简介 |

---

### `py/`
Python 工具脚本。
| 文件 | 说明 |
|------|------|
| `eyeriss_model.py` | **核心**：Eyeriss 硬件的行为级 Python 模型，含 Q3.13 定点卷积、padding、pooling、ReLU |
| `gen_test_data.py` | 生成测试激励数据 |
| `gen_tiny_config.py` | 生成 tiny 配置（3×2 PE 测试配置） |

---

### `tb/`
测试平台文件（SystemVerilog）。
| 文件 | 说明 |
|------|------|
| `shared_pkg.sv` | 共享信号定义包 |
| `tb_smoke.sv` | 冒烟测试：编译通过 + 复位 + 基本信号连接 |
| `tb_tiny_test.sv` | Tiny 配置测试（3×2 PE 阵列） |
| `tb_selfcheck.sv` | 自检验 TB（开发中） |

---

### `config/`
| 路径 | 说明 |
|------|------|
| `tiny/` | Tiny 测试配置（8 个 txt 文件 + serial_data.txt） |

---

### `test_data/`
| 文件 | 说明 |
|------|------|
| `ifmap_64.txt` | 64-bit packed ifmap 测试数据 |
| `filter_64.txt` | 64-bit packed filter 测试数据 |
| `bias_64.txt` | 64-bit packed bias 测试数据 |
| `expected_output_64.txt` | 期望输出 (64-bit packed) |

---

### 论文相关
| 文件 | 说明 |
|------|------|
| `论文_初稿.md` | ~12000 字毕业论文初稿 (Markdown) |
| `论文_提纲_给指导老师.md` | 论文提纲：结构 + 创新点论述 |
| `论文模板&格式参考/` | 学校论文模板 (docx + pdf) + 2 篇参考论文 |
| `README.md` | 项目说明 |

---

## 使用说明
- 这是**交付给指导老师的正式产出目录**
- `rtl/` 是参考代码，`rtl_annotated/` 是带注释的学习版本
- `docs/` 适合作为论文的技术附录素材
- 论文在 `论文_初稿.md`，需要补充图表和扩充文字
