# Eyeriss v1 RS数据流加速器 — 毕设工程

基于 MIT Eyeriss v1 (Chen et al., JSSC 2017) 的 Row-Stationary 数据流 CNN 加速器实现。

## 工程结构

```
H:\moateff_bench\
├── README.md                    # 本文件
│
├── rtl/                         # RTL硬件设计 (35个核心文件)
│   ├── EYERISS.sv               #   顶层模块
│   ├── scheduler.sv             # ★ 调度器 (毕设核心, 9状态FSM)
│   ├── pe.v                     # ★ PE处理单元
│   ├── pe_controller.sv         #   PE控制器 (6状态)
│   ├── pe_wrapper.v             #   PE封装 (FIFO + PE)
│   ├── pe_array.sv              #   PE阵列 (12×14 = 168 PE)
│   ├── processing_unit.sv       #   处理单元顶层
│   ├── glb_unit.sv              #   全局缓存顶层
│   ├── ifmap/filter/psum/bias_glb.sv  # 各GLB实现
│   ├── dual_bram.sv             #   双端口BRAM
│   ├── gin.sv / gon.sv          #   NoC输入/输出网络
│   ├── gin_wrapper.sv / gon_wrapper.sv
│   ├── noc_controller.sv        #   NoC控制器
│   ├── noc_wrapper.sv           #   NoC封装
│   ├── pass_controller.sv       #   Pass序列控制器
│   ├── ifmap/filter/psum_index_generator.sv  # 地址生成器
│   ├── mapper.sv                #   4D→1D地址映射
│   ├── scan_chain.sv            #   串行配置链
│   ├── relu.sv / relu_array.sv  #   ReLU激活
│   ├── sync_fifo.v              #   同步FIFO
│   ├── pe_multiplier.v          #   乘法器
│   ├── pe_adder.v               #   加法器
│   ├── pe_truncator.v           #   截位器
│   ├── interface_unit.sv        #   片外接口单元
│   └── async_fifo.sv            #   异步FIFO
│
├── tb/                          # 测试平台
│   ├── shared_pkg.sv            #   参数定义包
│   ├── tb_smoke.sv              #   冒烟测试 (验证scheduler FSM)
│   ├── tb_tiny_test.sv          #   小规模端到端自检测试
│   └── tb_selfcheck.sv          #   通用自检测试平台
│
├── py/                          # Python行为模型与工具
│   ├── eyeriss_model.py         # ★ 周期精确行为模型 (Scheduler+NoC+PE+GLB)
│   ├── gen_tiny_config.py       #   自定义层配置生成器
│   └── gen_test_data.py         #   测试数据 + golden reference生成
│
├── config/tiny/                 # 自建测试层配置 (8×8×1, K=3×3)
│   ├── parameters.txt           #   层参数 (H,W,R,S,...)
│   ├── enables.txt              #   PE使能矩阵 (12×14)
│   ├── ipsum_ln_selectors.txt   #   PSum注入点
│   ├── opsum_ln_selectors.txt   #   PSum提取点
│   ├── ifmap_ids.txt            #   ifmap NoC路由ID
│   ├── filters_ids.txt          #   filter NoC路由ID
│   ├── ipsum_ids.txt            #   ipsum NoC路由ID
│   ├── opsum_ids.txt            #   opsum NoC路由ID
│   └── serial_data.txt          #   合并后的scan chain位流
│
├── test_data/                   # 生成的测试数据
│   ├── ifmap_64.txt             #   ifmap (64-bit packed, Q3.13)
│   ├── filter_64.txt            #   filter
│   ├── bias_64.txt              #   bias
│   └── expected_output_64.txt   #   期望输出 (golden reference)
│
└── docs/                        # 文档
    ├── STUDY_GUIDE.md           # ★ 代码学习指南 (带注释, 按模块讲解)
    ├── ARCHITECTURE.md          #   硬件架构详细文档
    ├── BEHAVIORAL_MODEL.md      #   Python行为模型使用说明
    ├── FILE_GUIDE.md            #   原始项目文件说明
    └── PROGRESS.md              #   验证进度与问题记录
```

## 快速开始

### 编译RTL
```bash
cd H:/moateff_bench
VIVADO="E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin"
$VIVADO/xvlog -sv rtl/*.sv rtl/*.v tb/shared_pkg.sv
$VIVADO/xelab -timescale 1ns/1ps -L xil_defaultlib -s top_sim eyeriss_tb
```

### 运行行为模型
```bash
python py/eyeriss_model.py
```

### 生成自定义测试
```bash
# 1. 编辑 py/gen_tiny_config.py 修改层参数
# 2. 运行生成配置
python py/gen_tiny_config.py
# 3. 生成测试数据
python py/gen_test_data.py
```

## 目标卷积层

本课题目标层: Conv2D, IFM 16×16×32 → OFM 16×16×64, K=3×3, stride=1, pad=1

对应配置参数: H=18, W=18, R=3, S=3, E=16, F=16, C=32, M=64, N=1, U=1

## 关键参数说明

| 参数 | 含义 | 示例值 |
|------|------|--------|
| H,W | ifmap高/宽 | 8×8 |
| R,S | filter高/宽 | 3×3 |
| E,F | ofmap高/宽 | 6×6 |
| C | 输入通道数 | 1 |
| M | 输出通道(滤波器)数 | 1 |
| U | 步长 | 1 |
| m | 每pass组滤波器数 | 1 |
| n | 每pass组ifmap数 | 1 |
| e | OFM tile高度 | 6 |
| p | 水平PE并行度 | 1 |
| q | 通道并行度 | 1 |
| r | 列组数(通道级) | 1 |
| t | 行组数(滤波器级) | 1 |

## 数据精度

Q3.13 定点格式: 16-bit有符号, 1符号+2整数+13小数, 范围[-4.0, 3.9999]

## 验证状态

- [x] RTL编译 (71文件, 0错误)
- [x] 全系统elaboration
- [x] Scheduler FSM运行
- [x] Scan chain配置加载
- [x] Python行为模型与RTL算法一致性
- [ ] 全系统端到端仿真 (NoC集成调试中, 详见 docs/PROGRESS.md)

## 参考

- Chen et al., "Eyeriss: An Energy-Efficient Reconfigurable Accelerator for Deep CNNs", JSSC 2017
- Chen et al., "Eyeriss: A Spatial Architecture for Energy-Efficient Dataflow for CNNs", ISCA 2016
- Sze et al., "Efficient Processing of Deep Neural Networks: A Tutorial and Survey", Proc. IEEE 2017
