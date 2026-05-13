# moateff_trace/ — 目录介绍

> 用途：**分析产出主目录** — 所有深入分析、验证、Debug、AlexNet 数据准备工作的汇总。

---

## 一级目录与文件

### 顶层文档

#### `STATUS_SUMMARY.md`
**项目总状态文档** (2026-05-12)。包含：
- 所有已完成工作清单
- 关键发现总结（架构 6 项 + 仿真 4 项 + 子项目 3 项）
- 待解决问题（紧迫 3 项 + 重要 3 项 + 后续 3 项）
- 推荐下一步（方案 B→C→A 优先级）
**这是接手项目后应首先阅读的文件。**

#### `01_AUTHOR_EVOLUTION.md`
**作者 4 子项目演化分析** (~30KB)
- P1 (C Data Delivery): 所有 7 个文件的详细分析，调度器/Index Gen 算法描述，Bug 分析
- P2 (PE Standalone): 所有源文件清单 + PE 结构分析
- P3 (NoC Standalone): GIN/GON 架构分析
- P4 (Full System): 完整目录结构 + 与 P1-P3 的对比
- 关键结论：C→RTL 算法忠实保留，PE/NoC 逻辑与独立版一致

#### `02_ALEXNET_WEIGHTS.md`
**AlexNet 权重提取记录**
- PyTorch 预训练模型提取方法
- Q3.13 量化流程
- 5 层 Conv 权重/偏置的文件清单
- 测试图片选择和准备

#### `03_QA_COMPREHENSIVE.md`
**综合问答** — 对 question.txt 中所有问题的汇总回答

---

### `alxnet_training/`
**AlexNet 激励数据准备**

#### 工具脚本
| 文件 | 说明 |
|------|------|
| `extract_alexnet_weights.py` | 从 PyTorch 预训练 AlexNet 提取并量化权重 |
| `README.md` | 完整使用说明：从提取到硬件格式的完整流程 |

#### 权重文件 (`weights_q313/`)
| 文件 | 说明 |
|------|------|
| `conv1_filter_16.txt` | Conv1 权重 16-bit 格式 |
| `conv1_filter_64.txt` | Conv1 权重 64-bit packed (4×16bit) |
| `conv1_bias_16.txt` | Conv1 偏置 16-bit |
| `conv1_bias_64.txt` | Conv1 偏置 64-bit packed |
| `conv2~5_filter_16.txt` | Conv2-5 权重 16-bit |
| `conv2~5_bias_16.txt` | Conv2-5 偏置 16-bit |

#### 测试图片
| 文件 | 说明 |
|------|------|
| `test_flower.jpg` | **推荐使用**：紫色花朵，224×224 RGB |
| `test_dog_full.jpg` | 全身狗照，224×224 |
| `test_dog_nose.jpg` | 狗鼻子特写（太小，不推荐） |
| `test_image.jpg` | 最早的测试图 |

#### Ifmap 数据 (`ifmap_data/`)
| 文件 | 说明 |
|------|------|
| `conv1_ifmap_q313.txt` | 全图 Q3.13 ifmap (227×227×3) |
| `conv1_ifmap_q313_flower.txt` | 花朵图 Q3.13 ifmap |
| `conv1_ifmap_64.txt` | 64-bit packed 全图 ifmap |
| `conv1_ifmap_seg1_64.txt` ~ `seg8_64.txt` | 8 段切分 64-bit packed ifmap |
| `conv1_ifmap_flower_seg1_64.txt` ~ `seg8_64.txt` | 花朵图 8 段切分 |

> 注：8 段切分是因为 Eyeriss 的 GLB 深度有限（tile 级），无法一次容纳整个 ifmap。每段是原始图像的一个水平条带。

#### Golden Reference (`output/`)
| 文件 | 说明 |
|------|------|
| `conv1_ofmap_q313_golden.txt` | **最关键**：Conv1 期望输出 55×55×64 = 193,600 个 Q3.13 值 |
| `conv1_ofmap_64_golden.txt` | 64-bit packed 版本 |

---

### `task1_module_papers/`
**模块 RTL 详解** — 为毕业论文准备的技术深度文档

| 文件 | 大小 | 内容 |
|------|------|------|
| `01_SCHEDULER_RTL_DESCRIPTION.md` | 16KB | 9 状态 FSM 逐状态分析、5 个计数器逻辑、嵌套循环展开机制、参数传递到 NoC 的时序 |
| `02_PE_RTL_DESCRIPTION.md` | 24KB | 5 级 MAC 流水线逐级分析、6 状态 PE 控制器、ifmap/filter/psum 三种 Scratchpad 的读写时序、前向旁路机制、零跳过优化、12×14 阵列的 psum 空间累积 |
| `03_NOC_RTL_DESCRIPTION.md` | 28KB | PassCtrl 4 状态 FSM、4 通道 NoC 控制器、ifmap 的 5 级 index generator、filter/psum 的 lock-step index generator、mapper (4D→1D 地址映射公式)、tag generator (U + r×4 公式)、GIN 两级多播树、GON 反向聚合 |

**待补充**: GLB、Interface、ScanChain、ReLU 模块的类似详解文档

---

### `task2_author_verify/`
**作者 4 子项目追溯验证**

#### `COMPARISON_REPORT.md`
三个子项目 vs 最终版 (P4) 的详细对比报告：
- P1 (C Model) vs P4 (RTL Scheduler): 算法一致，H→D 参数适配
- P2 (PE Standalone) vs P4 (PE in Array): 数据路径完全一致，仅命名变化
- P3 (NoC Standalone) vs P4 (NoC in Array): 路由逻辑完全一致，仅 ID 加载方式不同

#### `p1_c_model/`
| 文件 | 说明 |
|------|------|
| `verify_c_algorithms.py` | Python 翻译的 C 算法 + 单元测试（含 lock-step 验证） |
| `p1_output/` | 测试输出目录 |

#### `p3_noc_standalone/`
| 文件 | 说明 |
|------|------|
| `rtl/` (14 文件) | 从 P3 复制的 NoC RTL |
| `tb_gin.sv` | 自建 GIN 测试平台（7 个测试用例） |
| `tb_gon.sv` | 自建 GON 测试平台（7 个测试用例） |
| `tb_noc.sv` | NoC 集成测试 |
| `webtalk*.log` | Vivado 仿真日志 |
| `xsim.dir/` | 仿真编译产物 |

---

### `task4_debug_backup/`
**Debug 过程的数据备份**

#### `config_original/`
原始配置文件（未经修改），用于对比验证修复效果。
包含：
- `config_script.py` (原始版)
- `conv1/` ~ `conv5/` (每层 9 个文件)
- `tiny/` (8 个文件)

#### `config_script_fixed.py`
**修复尝试版** — 尝试修复 config_script.py 的两个 bug：
1. 移除首 bit 重复
2. 从 `reversed(full_chain)` 改为 forward 顺序

**结果**: 修复不成功。forward 顺序给出 all-1s（最大值），LSB-first 方式也给出 all-1s。根因是 cfg_scan_chain 全系统加载的时序问题，而非单纯的位序。

---

### `debug_campaign/`
**全系统仿真 Debug 活动目录**

#### 配置文件
| 文件 | 说明 |
|------|------|
| `tiny_config_lf.txt` | Tiny 配置 (line-feed 分隔) |
| `serial_lsb_first_lf.txt` | LSB-first 版本配置 |
| `forward_tiny_lf.txt` | Forward 顺序配置 |
| `correct_tiny_lf.txt` | 尝试修复的正确配置 |
| `lsb_tiny_lf.txt` | LSB 版本配置 |

#### 测试平台 (`tb/`)
| 文件 | 仿真结果 | 关键发现 |
|------|---------|---------|
| `tb_debug_step1.sv` | ✅ 编译通过 | 首次全系统编译成功 |
| `tb_debug_fast.sv` | 快速冒烟 | 缩短仿真时间的精简版 |
| `tb_debug_v2.sv` | Scheduler→PROCESS, PassCtrl→PROCESSING, NoC done=0 | **最完整的 Debug TB**，含 GLB backdoor 写入 + 手动 start_pass |
| `tb_debug_v3.sv` | GIN tag 产生但异常 | NoC 内部探针深度分析 |
| `tb_debug_v4.sv` | e=24,p=4,q=5,r=0,t=6 (应为 6,1,1,1,1) | **参数 dump 验证**，确认扫描链参数 misalignment |
| `tb_debug_v5.sv` | force 参数后 NoC 仍停转 | force 方法验证 |
| `tb_debug_v6.sv` | force 生效但 ~50 周期后停止 | 确认参数修正仍不够，PE 配置段也可能错误 |
| `tb_scan_test.sv` | H=8 ✅ LSB-first, H=16 ❌ MSB-first | **独立扫描链测试**，证明 scan_ff 硬件是 LSB-first |
| `tb_scan_final.sv` | 全 92-bit LSB-first 加载 | 完整 tiny 配置加载验证 |

#### 日志和编译产物
| 文件/目录 | 说明 |
|-----------|------|
| `xelab.log`, `xvlog.log` | 编译日志 |
| `webtalk*.log`, `xsim*.log` | 仿真运行日志 |
| `xsim.dir/` | 仿真编译产物 (各模块 .sdb 数据库文件) |
| `logs/step1.log`, `logs/step1_run.log` | step1 仿真日志 |
| `STATUS.md` | Debug 活动状态记录 |
| `README.md` | Debug 目录说明 |

---

## 使用说明
- 顶层 3 个 .md 文件 + STATUS_SUMMARY.md 是快速了解全局的入口
- task1_module_papers/ 是毕业论文的**核心技术章节素材**
- task2_author_verify/ 是证明"作者设计忠实性"的证据
- debug_campaign/ 的 v2→v6→scan 序列记录了完整的 Debug 推理链条
- alxnet_training/ 的 Golden Reference 是硬件验证的**最终评判标准**
