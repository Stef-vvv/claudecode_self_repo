# Eyeriss v1 硬件验证进度报告

## 日期: 2026-05-09

## 1. 项目来源

`H:/complete_version/moateff/2025_11_1_Eyeriss-v1-main` — 基于MIT Eyeriss v1论文的SystemVerilog实现。

## 2. 已完成验证项

### 2.1 RTL编译 (通过)
- 71个RTL源文件 + 8个SystemVerilog Package
- Vivado 2020.2 xvlog: **零错误**, 零警告(除端口位宽不匹配warning)
- 模块层次: eyeriss → scheduler + processing_unit(pe_array + noc_wrapper) + glb_unit + interface_unit + relu + scan_chain
- PE阵列: 12行×14列 = 168 PE, 每个PE含ifmap_spad(12) + filter_spad(224) + psum_spad(24)
- NoC: GIN(组播输入) + GON(汇聚输出), 两级标签路由

### 2.2 全系统Elaboration (通过)
- xelab: 成功构建仿真快照
- 修复bug: EYERISS.sv中2处端口/参数名不匹配
  - scan_chain: .se/.si/.so → .scan_en/.scan_in/.scan_out
  - glb_unit: .DEPTH_xxx → .IFMAP_GLB_DEPTH等

### 2.3 Scheduler FSM (通过)
- 调度器9状态FSM正确运行
- start信号触发 IDLE→CHECK, start_pass触发 CHECK→START_PASS→PROCESS
- busy信号正确置位, 证明调度器进入PROCESS状态

### 2.4 Scan Chain配置 (通过)
- 原Conv1配置(10935 bits)成功加载
- 自建tiny test配置(3644 bits)成功加载
- 17个参数寄存器 + PE使能矩阵 + NoC路由ID全部可配置

### 2.5 自建测试框架
- Python脚本 gen_tiny_config.py: 生成任意层配置(parameters + enables + NoC IDs + serial_data.txt)
- Python脚本 gen_test_data.py: 生成Q3.13测试数据 + golden reference
- 自检testbench框架: tb_tiny_test.sv, tb_smoke.sv

## 3. 当前阻塞问题

### 3.1 全系统仿真无法完成
- **现象**: Scheduler进入PROCESS状态(busy=1)后, noc_done信号永不置位
- **影响范围**: Conv1原配置和自建tiny配置均出现相同问题
- **超时测试**: 200K+时钟周期仍无法完成(预期应在~50K周期内完成)

### 3.2 根因分析(推测)
1. **NoC→PE数据流死锁**: GIN标签匹配可能失败, 导致FIFO满→NoC控制器无法推送→死锁
2. **时钟域交叉**: PE controller使用negedge clk, NoC/FIFO使用posedge clk, 半周期偏移可能导致握手失败
3. **原项目未完成集成验证**: load_pkg.sv全部注释, run_conv2~5只有空壳, 原开发者可能从未跑通全系统仿真

### 3.3 证据
- 原testbench (`test_pkg.sv`) 只调用 `run_conv1()`, conv2-5被注释
- `load_pkg.sv` 所有数据加载task被注释
- 仓库中无任何测试数据文件(.txt/.mem)
- `run_conv2~5()` 仅调用配置, 不启动scheduler, 不加载数据

## 4. 后续计划

### 4.1 Python全系统行为模型
- 周期精确建模scheduler + NoC + PE + GLB
- 可生成任意层golden reference
- 与RTL仿真结果对比验证

### 4.2 组件级验证
- PE核心独立测试
- Scheduler状态机覆盖测试
- GLB读写测试
- NoC路由单元测试

### 4.3 文档
- 硬件架构说明
- 模块接口定义
- 使用指南
