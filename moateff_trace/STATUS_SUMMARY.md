# Eyeriss v1 项目总状态 — 2026-05-12

## 一、已完成工作

### 1. 项目理解与文档
| 产出 | 位置 | 状态 |
|------|------|------|
| 硬件架构文档 | `H:/moateff_bench/docs/ARCHITECTURE.md` | ✅ |
| Python行为模型 | `H:/moateff_bench/py/eyeriss_model.py` | ✅ |
| 代码学习指南(STUDY_GUIDE) | `H:/moateff_bench/docs/STUDY_GUIDE.md` | ✅ |
| 时钟沿分析(negedge为主) | `H:/moateff_bench/docs/CLOCK_EDGE_ANALYSIS.md` | ✅ |
| RTL注释版(71文件) | `H:/moateff_bench/rtl_annotated/` | ✅ |
| 硬件框图 | `H:/moateff_bench/rtl_annotated/00_BLOCK_DIAGRAM.md` | ✅ |
| 论文提纲 | `H:/moateff_bench/论文_提纲_给指导老师.md` | ✅ |
| 论文初稿(~12000字) | `H:/moateff_bench/论文_初稿.md` | ✅ |

### 2. Q&A 问题解答
| 问题 | 位置 | 状态 |
|------|------|------|
| Q1: 必须跑AlexNet? | `H:/moateff_QaR/Q1_AlexNet_Config.md` | ✅ |
| Q3: GLB 25bank vs 4bank | `H:/moateff_QaR/Q3_GLB_Banks.md` | ✅ |
| Q4: Filter 64bit vs ifmap 16bit | `H:/moateff_QaR/Q4_Data_Width.md` | ✅ |
| Q5: 扫描链配置原理 | `H:/moateff_QaR/Q5_Scan_Chain.md` | ✅ |
| Q6: GLB深度数值原因 | `H:/moateff_QaR/Q6_GLB_Depths.md` | ✅ |
| 扫描链完整流程 | `H:/moateff_QaR/Q_SCAN_CHAIN_CONFIG_FLOW.md` | ✅ |

### 3. 作者子项目追溯与验证 (Task 2)
| 子项目 | 验证方式 | 结果 | 位置 |
|--------|---------|------|------|
| P1: C Data Delivery | Python翻译+单元测试 | ✅ 4/4算法通过 | `task2_author_verify/p1_c_model/` |
| P2: PE Standalone | Vivado编译 | ⚠️ 工具不兼容(typedef enum) | `task2_author_verify/p2_pe_standalone/` |
| P3: NoC Standalone | 自建TB+仿真 | ✅ GIN 7/7 + GON 6/7 | `task2_author_verify/p3_noc_standalone/` |
| 对比报告 | 三项目vs最终版 | ✅ 核心逻辑一致 | `task2_author_verify/COMPARISON_REPORT.md` |

### 4. 模块RTL详解 (Task 1)
| 模块 | 内容 | 位置 |
|------|------|------|
| Scheduler | 9状态FSM, 5计数器, 嵌套循环 | `task1_module_papers/01_SCHEDULER_RTL_DESCRIPTION.md` (16KB) |
| PE | 5级MAC, 6状态控制器, 前向旁路, 零跳过 | `task1_module_papers/02_PE_RTL_DESCRIPTION.md` (24KB) |
| NoC | PassCtrl, 4路通道, 索引生成, lock-step, GIN/GON | `task1_module_papers/03_NOC_RTL_DESCRIPTION.md` (28KB) |

### 5. AlexNet激励数据 (Task 2)
| 产出 | 内容 | 位置 |
|------|------|------|
| 5层Conv权重 | PyTorch预训练→Q3.13量化 | `alxnet_training/weights_q313/` (10文件) |
| 测试图片 | 花朵(推荐), 狗全身 | `alxnet_training/test_flower.jpg` 等 |
| Golden Reference | Conv1 55×55×64 = 193,600值 | `alxnet_training/output/conv1_ofmap_q313_golden.txt` |
| 硬件格式 | 64-bit packed + 8段ifmap | `alxnet_training/ifmap_data/` |
| 使用说明 | 完整流程 | `alxnet_training/README.md` |

### 6. 全系统仿真Debug (Task 4)
| 阶段 | 发现 | TB文件 |
|------|------|--------|
| v2 | Scheduler→PROCESS, PassCtrl→PROCESSING, NoC done=0 | `tb_debug_v2.sv` |
| v3 | NoC内部探针: gin_full=0, we/re活跃, tag产生但异常 | `tb_debug_v3.sv` |
| v4 | 参数dump: 扫描链后全0, 10周期延迟, e/p/q/r/t错 | `tb_debug_v4.sv` |
| v5 | force修正参数后NoC仍停转 | `tb_debug_v5.sv` |
| v6 | 确认force生效, 参数修正后NoC继续异常 | `tb_debug_v6.sv` |
| scan | 独立测试: LSB-first编码正确(H=8✅), MSB-first错误 | `tb_scan_test.sv` |

### 7. 源码改动记录
| 改动 | 位置 | 说明 |
|------|------|------|
| EYERISS.sv 端口名 | `H:/moateff_revise_comparison/CHANGES.md` | .se/.si/.so→.scan_en/.scan_in/.scan_out |
| EYERISS.sv 参数名 | 同上 | .DEPTH_xxx→.XXX_GLB_DEPTH |
| cfg_pkg.sv 路径 | 同上 | D:/data→H:/moateff_test |
| file_pkg.sv 路径 | 同上 | .../log.txt→H:/moateff_test/sim/log.txt |

### 8. CLAUDE.md
| 文件 | 状态 |
|------|------|
| `H:/cc_project/CLAUDE.md` | ✅ 已更新, 涵盖moateff全项目 |

---

## 二、关键发现总结

### 架构层
1. **negedge为主时钟沿(88%)** — Scheduler用posedge是有意设计, 不是bug
2. **Scheduler需要start_pass外部脉冲** — 原作者从未实现外部控制器
3. **NoC done = opsum_done** — 只等opsum, 忽略其他3路
4. **GLB简化**: 固定4实例≠论文25可重构bank
5. **Filter 64-bit NoC**: 4×16打包减少4倍传输
6. **GLB深度为tile级**: 非layer级, 按公式Derived from p,q,r,t等参数

### 仿真层
7. **扫描链参数misalignment**: config_script.py有首bit重复bug + 整个链反转
8. **LSB-first编码**: 扫描链要求每参数内部位序反转(独立测试验证H=8)
9. **cfg_scan_chain在全系统中有未解决的时序问题**
10. **全系统NoC死锁**: 参数错误导致GIN标签不匹配 → PE不收数据 → opsum不完成

### 子项目层
11. **C模型→RTL算法忠实**: lock-step机制原封保留, 仅H→D参数适配
12. **独立版PE与最终版完全一致** (仅命名/语法变化)
13. **独立版NoC路由逻辑与最终版完全一致** (仅ID加载方式从端口→扫描链)

---

## 三、待解决问题

### 紧迫
1. **cfg_scan_chain全系统加载bug**: 独立测试LSB-first正确, 但全系统中加载后参数全是1
2. **扫描链配置位序**: 作者的设计意图不清(config_script.py反转载荷)
3. **全系统NoC死锁**: 即使参数修正, NoC仍在~50周期后停转

### 重要
4. **task2 P2验证**: PE standalone无法用Vivado 2020.2编译, 是否需要修复/替代验证?
5. **task2 P3补充**: GON standalone只测了标签匹配, 未测数据流
6. **PE配置段验证**: 参数正确后PE enables/NoC IDs是否也正确?

### 后续
7. **task1补充**: GLB/Interface/ScanChain/ReLU模块未写RTL详解
8. **论文初稿扩充**: ~12000字→13000字, 补图补表
9. **Verilator加速**: xsim太慢, 考虑用Verilator

---

## 四、建议下一步

### 方案A: 继续查cfg_scan_chain bug (需深入时序分析)
1. 简化cfg_scan_chain逻辑, 绕过文件I/O
2. 对比手动shift和cfg_scan_chain的时序差异
3. 修复后重新生成正确tiny配置

### 方案B: 绕过扫描链, 直接用force验证NoC/PE (实用)
1. force设置正确参数(已确认force在SCAN_CHAIN/SCHEDULER有效)
2. force设置PE enables和NoC IDs
3. 用v6框架跑完整pass
4. 对比硬件ofmap vs Python Golden Reference

### 方案C: 先完成文档+论文 (为毕设交差)
1. 补task1剩余模块
2. 扩充论文初稿
3. 插入图表

**推荐顺序: B → C → A**
先验证核心功能(即使绕过扫描链), 再写文档, 最后回头修扫描链bug。
