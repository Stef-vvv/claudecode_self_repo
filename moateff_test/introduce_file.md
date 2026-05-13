# moateff_test/ — 目录介绍

> 用途：**活跃工作副本** — 实际运行编译和仿真的目录。基于 P4 全系统，已应用 4 项修改（见 moateff_revise_comparison/CHANGES.md）。

---

## 一级目录与文件

### 编译脚本
| 文件 | 说明 |
|------|------|
| `compile.sh` | bash 编译脚本：xvlog 编译所有 RTL + Package |
| `compile.tcl` | Vivado Tcl 编译脚本（备选） |
| `compile_pkg.log` | Package 编译日志 |
| `compile_rtl.log` | RTL 编译日志 |

### `config/`
扫描链配置数据和生成脚本。
| 路径 | 说明 |
|------|------|
| `config_script.py` | 扫描链配置生成脚本 |
| `conv1/` ~ `conv5/` | AlexNet Conv1~5 的配置 (parameters.txt + enables.txt + 6 个 ID/LN 文件 + scan_chain.txt + serial_data.txt) |
| `tiny/` | 小型测试配置 (H=8,W=8 的简化参数) |

每层配置文件（8 个）：
| 文件 | 内容 | 示例行数 |
|------|------|---------|
| `parameters.txt` | 17 个 CNN 参数键值对 | 17 行 |
| `enables.txt` | 12×14 PE 使能矩阵 (0/1) | 12 行 × 14 列 |
| `filters_ids.txt` | 12 行 filter NoC 路由 ID | 12 行 × 15 列 |
| `ifmap_ids.txt` | 12 行 ifmap NoC 路由 ID (首列 4-bit, 其余 5-bit) | 12 行 × 15 列 |
| `ipsum_ids.txt` | 12 行 ipsum NoC 路由 ID | 12 行 × 15 列 |
| `opsum_ids.txt` | 12 行 opsum NoC 路由 ID | 12 行 × 15 列 |
| `ipsum_ln_selectors.txt` | 12×14 输入 LN 选择器 | 12 行 × 14 列 |
| `opsum_ln_selectors.txt` | 12×14 输出 LN 选择器 | 12 行 × 14 列 |

### `docs/`
| 文件 | 说明 |
|------|------|
| `ARCHITECTURE.md` | 硬件架构文档 |
| `BEHAVIORAL_MODEL.md` | 行为模型说明 |
| `FILE_GUIDE.md` | 文件索引 |

### `src/` & `sim/`
RTL 源码和仿真 Package — **这是实际编译使用的文件**。
内容与 `moateff/2025_11_1_.../src/` 和 `sim/` 相同（已应用 4 项修改）。

### `pe_standalone/`
从 P2 复制来的 PE standalone 测试环境。
| 路径 | 说明 |
|------|------|
| `sim/PE_tb.sv` | PE 测试平台 |
| `sim/run_all.tcl` | 批量仿真 Tcl 脚本 |
| `sim/ifmap_data.mem` | Ifmap 测试数据 |
| `sim/filter_data.mem` | Filter 测试数据 |
| `sim/ipsum_data.mem` | Psum 输入测试数据 |
| `sim/expected_output.mem` | 期望输出 |
| `.mem/conv1~5/` | 5 层卷积测试向量 |
| `.mem/example1~3/` | 3 组简单测试向量 |
| `.png/` | 仿真结果截图 |
| `.xdc/Constraints_basys3.xdc` | Basys3 FPGA 约束文件 |
| `run_pe.sh` | PE 仿真运行脚本 |

---

## 使用说明
- **这是运行仿真的工作目录** — 编译和仿真命令在这里执行
- 编译命令见 `H:/cc_project/CLAUDE.md` 的 "Build & Simulation Commands" 节
- 配置文件在 `config/` 下，生成脚本有已知 bug（见 takeover.md）
- 修改 RTL 代码请先在此目录测试，确认无误后同步到 `moateff_bench/rtl/`
