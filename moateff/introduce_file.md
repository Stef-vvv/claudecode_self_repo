# moateff/ — 目录介绍

> 用途：moateff 作者 4 个子项目的**副本备份**。与 `complete_version/moateff/` 内容相同。

---

## 一级子目录

### `2025_7_18_Eyeriss-v1-Data-Delivery-Pattarn-main/` (P1)
**性质**: 纯 C 语言行为级模型，作者最早的项目
**内容**: `src/` 目录下 7 个文件
| 文件 | 用途 |
|------|------|
| `run.c` | 主程序入口，读取参数+调用调度器+协调 index generator |
| `Scheduler.c` | 3 层嵌套循环 (N→C→M)，划分 processing pass |
| `Array.c` | 4D 内存分配器 + 地址计算 |
| `ifmap_index_generator.c` | 5 层嵌套生成 ifmap 地址序列 |
| `filter_index_generator.c` | lock-step 级联递增 (p→q→S)，内层 4 循环 |
| `psum_index_generator.c` | lock-step 级联递增 (p→F→n)，内层 4 循环 |
| `parameter.txt` | 测试参数 (M=8,C=6,N=1,W=H=5,R=S=3,E=F=2...) |

**验证状态**: ✅ Python 翻译验证 4/4 算法通过

---

### `2025_7_23_Eyeriss-v1-Processing-Element-main/` (P2)
**性质**: PE 独立 RTL 验证，含完整 TB 和测试数据
**目录结构**:
| 目录/文件 | 说明 |
|-----------|------|
| `src/` | 20 个 RTL 源文件 (.v+.sv) |
| `sim/PE_tb.sv` | PE 测试平台 |
| `sw/` | C 工具程序: 1D_Convolution.c, Convert_to_binary.c, Random_data.c, run.c |
| `.mem/conv1~5/` | AlexNet 5 层卷积测试向量 (ifmap/filter/ipsum/expected) |
| `.mem/example1~3/` | 简单测试向量 (2×3 小 PE 阵列) |
| `.png/Conv1~4,5/` | 仿真波形截图 (parameters_to_sw, parameters_to_tb, results) |
| `.xdc/Constraints_basys3.xdc` | Basys3 FPGA 约束文件 |

**验证状态**: ⚠️ Vivado 2020.2 编译失败 (typedef enum 不兼容)，需旧版 Vivado 或手动修改

---

### `2025_8_23_Eyeriss-v1-Network-on-Chip-main/` (P3)
**性质**: NoC (GIN + GON) 独立 RTL 验证
**目录结构**:
| 文件 | 说明 |
|------|------|
| `src/gin.sv` | GIN 顶层：多播树根节点 |
| `src/gin_mcc.sv` | GIN 多播控制器：tag 匹配 + 路由决策 |
| `src/gin_xbus.sv` | GIN 交叉开关：4 输出通道 |
| `src/gin_fifo.sv` | GIN 端 FIFO |
| `src/gon.sv` | GON 顶层：聚合树根节点 |
| `src/gon_mcc.sv` | GON 多播控制器：反向聚合 |
| `src/gon_xbus.sv` | GON 交叉开关 |
| `src/gon_fifo.sv` | GON 端 FIFO |
| `src/fifo_mem.v`, `fifo_rd_ctrl.v`, `fifo_top.v`, `fifo_wr_ctrl.v` | 基础 FIFO 组件 |
| `run.sh` | 仿真脚本 |

**验证状态**: ✅ GIN 7/7 测试通过 + GON 6/7 测试通过 (自建 TB)

---

### `2025_11_1_Eyeriss-v1-main/` (P4)
**性质**: **全系统集成版 — 主工作对象**
**完整目录结构**:

#### `config/`
| 路径 | 说明 |
|------|------|
| `config_script.py` | 扫描链配置生成脚本 (有 bug: 反转 + 首 bit 重复) |
| `conv1/` ~ `conv5/` | 每层 8 个配置文件 (parameters.txt + enables.txt + 6 个 ID 文件) |
| `conv1~/serial_data.txt` | 扫描链串行数据 (由 config_script.py 生成) |
| `conv1~/scan_chain.txt` | 扫描链逐 bit 列表 |

#### `docs/`
| 文件 | 说明 |
|------|------|
| `eyeriss_isca_2016.pdf` | ISCA 2016 原始论文 |
| `eyeriss_jssc_2017.pdf` | JSSC 2017 期刊版 |
| `eyeriss_isscc_2016.pdf` | ISSCC 2016 演示 |
| 其他 .pdf | 衍生论文、slides、poster |
| `energy_estimation.png` | 能耗估算图 |

#### `model/`
| 路径 | 说明 |
|------|------|
| `alexnet/alexnet.py` | AlexNet PyTorch 推理 |
| `alexnet/alexnet_custom.py` | 自定义 AlexNet 变体 |
| `alexnet/apply_fcn.py` | FCN 应用 |
| `from_resize_to_pooling_colored.py` | 彩色图 resize→pooling |
| `from_resize_to_pooling_gray.py` | 灰度图 resize→pooling |
| `flow.txt` | 数据流说明 |
| `scripts/convolution.py` | **关键**: Q3.13 定点卷积（生成 Golden Reference 的核心算法） |
| `scripts/padding.py` | Padding 操作 |
| `scripts/pooling.py` | Pooling 操作 |
| `scripts/relu.py` | ReLU 激活 |
| `scripts/resize.py` | 图像缩放 |
| `utils/ifmap_segmentation.py` | Ifmap 8 段切分 (适配硬件) |
| `utils/jpeg_to_Q3.13_txt.py` | JPEG→Q3.13 文本转换 |
| `utils/diff.py` | 输出差异对比 |
| `utils/merge_split.py` | 数据合并/拆分 |

#### `sim/`
| 文件 | 说明 |
|------|------|
| `Eyeriss_tb.sv` | 原始顶层 TB (不含 start_pass, 无法正常工作) |
| `shared_pkg.sv` | 共享信号包 (时钟、复位、扫描链接口) |
| `cfg_pkg.sv` | 配置包 (文件路径、cfg_scan_chain task) |
| `file_pkg.sv` | 文件 I/O 包 |
| `glb_pkg.sv` | GLB 操作包 |
| `layer_pkg.sv` | 层参数包 (Conv1-5 参数) |
| `load_pkg.sv` | 数据加载包（内容被注释掉，从未完整实现） |
| `test_pkg.sv` | 测试控制包 |
| `fifo_if_pkg.sv` | FIFO 接口包 |

#### `src/` (71 RTL 文件)
| 路径 | 说明 |
|------|------|
| `EYERISS.sv` | **顶层模块**，例化所有子模块 |
| `scheduler.sv` | 9 状态 FSM 调度器 (posedge) |
| `GLB UNIT/` | 全局行缓冲：glb_unit.sv + ifmap/filter/bias/psum_glb.sv + dual_bram.sv + glb_flop.v |
| `PE Array/processing_unit.sv` | 处理单元顶层 (PE 阵列 + NoC) |
| `PE Array/Processing Element/` | PE 实现：pe.v, pe_controller.sv, pe_wrapper.v, pe_array.sv, pe_adder.v, pe_clk_gating.v, pe_flopr.v, pe_filter_spad.v, pe_ifmap_spad.v, pe_psum_spad.v, pe_mux2x1.v |
| `PE Array/Network on Chip/` | NoC: gin.sv, gin_mcc.sv, gin_xbus.sv, gon.sv, gon_mcc.sv, gon_xbus.sv, gin_wrapper.sv, gon_wrapper.sv + NoC Controller (ifmap/filter/ipsum/opsum 各有 index_gen + mapper + tag_gen + noc_controller + fifo) |
| `PE Array/Sync FIFO/` | 同步 FIFO 系列 (6 文件) |
| `SCAN CHAIN/` | 扫描链: scan_chain.sv, scan_ff.sv, scan_ff_Nbit.sv |
| `INTERFACE UNIT/` | 接口单元: interface_unit.sv + async_fifo 系列 (6 文件) + reset_sync.sv + clk_mux.sv + demux/mux |
| `RelU/` | ReLU: relu_array.sv, relu.sv |

#### 其他文件
| 文件 | 说明 |
|------|------|
| `parameters.docx` / `.pdf` | 参数说明文档（作者手写） |

**验证状态**: ⚠️ 可编译，但扫描链配置 bug + NoC 死锁未解决
