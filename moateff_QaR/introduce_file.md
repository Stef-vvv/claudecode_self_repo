# moateff_QaR/ — 目录介绍

> 用途：**技术问答与问题解答** — 回答导师/自提出的关键技术问题，以及全系统仿真 Debug 经验总结。

---

## 文件清单

### `Q1_AlexNet_Config.md`
**问题**: 硬件加速器是否必须跑 AlexNet？不同层的配置参数如何变化？
**内容**:
- AlexNet 5 层 Conv 的维度参数 (H/W/C/M/R/S/E/F)
- Eyeriss 硬件参数 (p,q,r,t,n,m,e) 的计算公式
- Conv1~5 每层的具体参数值
- 为什么必须用 AlexNet（标准 benchmark，论文对标）

---

### `Q3_GLB_Banks.md`
**问题**: RTL 中的 GLB 是 4 bank，但论文说的是 25 reconfigurable bank，为什么不同？
**内容**:
- 论文 GLB 架构：2 filter bank + (9 ifmap + 14 psum = 23) reconfigurable = 25 total
- RTL GLB 架构：4 固定实例 (U1_IFMAP, U2_FILTER, U3_BIAS, U4_PSUM)
- 差异原因：RTL 大幅简化了硬件实现，固定 bank 分配
- 每个 RTL GLB 内部有 4 个 dual_bram（共 16 个 BRAM block）

---

### `Q4_Data_Width.md`
**问题**: Filter NoC 为什么是 64-bit 而 ifmap NoC 是 16-bit？
**内容**:
- Filter 值 16-bit 但 4 个打包为 64-bit 经 NoC 传输
- PE 端 sync_fifo 解包 64→4×16
- 原因：p=16 filters 共享一个 PE，减少 4 倍 NoC 传输量
- Q3.13 定点格式详解 (1 sign + 2 int + 13 frac, range [-4.0, 3.99988])

---

### `Q5_Scan_Chain.md`
**问题**: 扫描链是什么？如何配置 CNN 参数和 PE 阵列？
**内容**:
- 扫描链 3644 bits 的两级结构：17 参数 (92b) + PE 配置 (3552b)
- PE 配置段 = enables (168b) + LN selectors (336b) + NoC IDs (3048b)
- scan_ff 硬件结构：negedge 触发的移位寄存器链
- 数据加载方式：scan_en=1 时串行移位，scan_en=0 时 latch 到输出

---

### `Q6_GLB_Depths.md`
**问题**: GLB 的深度值（如 ifmap=7945, filter=3872, psum=46656）是怎么来的？
**内容**:
- GLB 深度是 **tile 级**而非 layer 级
- 公式推导：IFMAP_GLB_DEPTH = H×W×n, FILTER_GLB_DEPTH = R×S×C×p×t 等
- Conv1~5 各层的深度值计算
- RTL 中的参数化机制 (H_WIDTH, W_WIDTH 等位宽参数)

---

### `Q_SCAN_CHAIN_CONFIG_FLOW.md`
**问题**: 扫描链的配置文件是怎么生成的？完整流程是什么？
**内容**:
- config_script.py 的完整工作流程
- 8 个输入文件格式说明 (parameters.txt, enables.txt, IDs 文件, LN selectors 文件)
- 3644-bit full_chain 的拼接顺序
- **发现的两个 bug**: (1) 首 bit 重复写入, (2) 整个链反转导致 PE 段跑到参数位置
- serial_data.txt 和 scan_chain.txt 的关系

---

### `EXPERIENCE_LOG.md`
**内容**: 全系统仿真 Debug 经验总结
- 仿真环境搭建 (Vivado 2020.2 xvlog/xelab/xsim 命令)
- 层次化路径记录 (哪些信号可访问，哪些不可)
- 关键架构发现 (时钟沿、start_pass、NoC done、GLB 简化等)
- **死锁根因证据链**：参数 misalignment → PE enables 全错 → 无 PE 激活 → NoC 停转
- 下一步行动计划

---

## 使用说明
- 这些文档是论文的重要技术素材来源
- Q1-Q6 是对导师可能提问的预研回答
- EXPERIENCE_LOG.md 是后续 Debug 的第一手参考资料
