# Eyeriss v1 RS数据流加速器 — 毕设项目

## 项目来源

基于 MIT Eyeriss v1 论文 (Chen et al., JSSC 2017) 的 Row-Stationary 数据流 CNN 加速器 SystemVerilog 实现。

原始代码来自 `H:/complete_version/moateff/2025_11_1_Eyeriss-v1-main`，本项目对其进行了：
- 编译验证（Vivado 2020.2，71个RTL文件零错误）
- 接口bug修复（端口名/参数名不匹配）
- Python行为级模型搭建
- 测试框架构建
- 配置生成工具开发

## 目录结构

```
H:/moateff_test/
├── README.md                    # 本文件
├── PROGRESS.md                  # 验证进度与问题记录
├── compile.sh / compile.tcl     # Vivado编译脚本
│
├── src/                         # RTL源代码 (71文件)
│   ├── EYERISS.sv               # 顶层模块
│   ├── scheduler.sv             # 调度器 (9状态FSM, 嵌套循环)
│   ├── GLB UNIT/                # 全局缓存 (ifmap/filter/psum/bias)
│   ├── INTERFACE UNIT/          # 片外存储接口 (异步FIFO)
│   ├── PE Array/
│   │   ├── processing_unit.sv   # 处理单元顶层
│   │   ├── Processing Element/  # PE核心 (MAC, SPAD, 控制器)
│   │   ├── Network on Chip/     # GIN/GON 数据分发网络
│   │   └── Sync FIFO/           # 同步FIFO
│   ├── RelU/                    # ReLU激活函数
│   └── SCAN CHAIN/              # 串行配置链
│
├── sim/                         # 仿真文件
│   ├── shared_pkg.sv            # 参数定义 (AlexNet Conv1-5)
│   ├── Eyeriss_tb.sv            # 原始测试平台 (数据加载未完成)
│   ├── tb_smoke.sv              # 冒烟测试 (验证scheduler FSM)
│   ├── tb_tiny_test.sv          # 小规模端到端自检测试
│   ├── tb_selfcheck.sv          # 自检测试平台
│   └── *.sv                     # 其他package文件
│
├── config/                      # 配置文件
│   ├── config_script.py         # 配置生成脚本
│   ├── conv1/ ~ conv5/          # AlexNet Conv1-5 配置
│   └── tiny/                    # 自建小规模测试层配置
│
├── py/                          # Python行为模型与工具
│   ├── eyeriss_model.py         # 周期精确行为级模型
│   ├── gen_tiny_config.py       # 配置生成器
│   └── gen_test_data.py         # 测试数据生成器
│
├── test_data/                   # 生成的测试数据
│   ├── ifmap_64.txt             # ifmap数据 (64-bit packed)
│   ├── filter_64.txt            # filter数据
│   ├── bias_64.txt              # bias数据
│   └── expected_output_64.txt   # 期望输出 (golden reference)
│
└── docs/                        # 文档 (待完善)
```

## 硬件架构

```
                    ┌─────────────┐
     off-chip  ←──→ │ Interface   │ (async FIFO, 跨时钟域)
       DRAM         │ Unit        │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
         ┌────▼───┐  ┌────▼───┐  ┌────▼───┐
         │ IFMAP  │  │ FILTER │  │ PSUM   │  GLB
         │ GLB    │  │ GLB    │  │ GLB    │  (4-bank BRAM)
         └────┬───┘  └────┬───┘  └────┬───┘
              │            │            │
         ┌────▼────────────▼────────────▼───┐
         │         NoC Controller           │
         │  (Index Generators + Mappers)    │
         └────┬────────────────────────┬────┘
              │                        │
         ┌────▼────┐              ┌────▼────┐
         │   GIN   │ (multicast)  │   GON   │ (gather)
         └────┬────┘              └────▲────┘
              │                        │
         ┌────▼────────────────────────┴────┐
         │         PE Array (12×14)         │
         │   ┌───┐ ┌───┐     ┌───┐         │
         │   │PE │ │PE │ ... │PE │  Row 0  │
         │   └─▲─┘ └─▲─┘     └─▲─┘         │
         │     │     │         │  (psum↑)   │
         │   ┌─┼─┐ ┌─┼─┐     ┌─┼─┐         │
         │   │PE │ │PE │ ... │PE │  Row 1  │
         │   └───┘ └───┘     └───┘         │
         └─────────────────────────────────┘
              │                        │
         ┌────▼────┐                   │
         │   ReLU  │◄──────────────────┘
         └─────────┘
```

### 关键参数
- PE阵列: 12行×14列 = 168 PE
- 每PE: ifmap SPAD(12深) + filter SPAD(224深) + psum SPAD(24深)
- 数据精度: Q3.13 定点 (16-bit)
- GLB: 4组双端口BRAM

### 数据流 (Row-Stationary)
1. Scheduler 生成嵌套循环 pass 描述 (filter_ids, channel_ids, ifmap_ids)
2. NoC Controller 的 Index Generator 遍历每个 pass 的地址空间
3. Mapper 将 4D 坐标映射为 GLB 线性地址
4. GIN 通过两级标签路由将数据组播到匹配的 PE
5. 每个 PE 执行 1D 卷积 (ifmap_row × filter_row)
6. PSum 在列内垂直向上流动 (PE[i+1] → PE[i])
7. 顶部 PE 的累积结果经 GON 写回 PSum GLB

## 快速开始

### 编译
```bash
cd H:/moateff_test
# 使用 Vivado 2020.2
source compile.sh    # 编译全部RTL + 原始testbench
```

### 行为模型
```bash
python py/eyeriss_model.py    # 运行Python行为模型
python py/gen_tiny_config.py  # 生成自定义层配置
python py/gen_test_data.py    # 生成测试数据
```

### 运行仿真
```bash
# 冒烟测试 (验证scheduler)
E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin/xsim smoke_sim -R

# 小规模端到端测试
E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin/xsim tiny_sim -R
```

## 已验证项
- [x] RTL编译 (71文件, 0错误)
- [x] 全系统elaboration
- [x] Scheduler FSM运行
- [x] Scan chain配置加载
- [x] Python行为模型与RTL算法一致性
- [ ] 全系统端到端仿真 (NoC集成调试中)

## 参考
- Chen et al., "Eyeriss: An Energy-Efficient Reconfigurable Accelerator for Deep CNNs", JSSC 2017
- Chen et al., "Eyeriss: A Spatial Architecture for Energy-Efficient Dataflow for CNNs", ISCA 2016
