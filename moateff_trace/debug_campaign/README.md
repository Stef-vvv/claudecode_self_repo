# Eyeriss v1 全系统仿真Debug记录

## 目标

用真实数据（AlexNet Conv1或tiny测试层）跑通全系统仿真，定位noc_done死锁原因。

## 已验证项

| # | 测试项 | 方法 | 结果 |
|---|--------|------|------|
| 1 | RTL全量编译 | xvlog 71文件 | 零错误 ✅ |
| 2 | 系统Elaboration | xelab全系统 | 成功 ✅ |
| 3 | Scheduler FSM启动 | tb_smoke + Conv1 scan chain | busy=1 ✅ |
| 4 | GLB后门写入 | hierarchical force mem | 待验证 |
| 5 | Scan chain加载(cfg_pkg) | cfg_scan_chain task | 运行中... |
| 6 | NoC启动 | 观察pass_controller state | 待做 |

## 当前阻塞

**仿真速度**: 扫描链3644 bits，每个bit需要1个core_clk周期(10ns)，共36,440ns。但仿真中包含168个PE的全量逻辑评估，每周期都很慢。cfg_scan_chain正在加载中。

## Debug步骤计划

Step 1: GLB后门写入 + Scan chain加载 → 验证配置正确
Step 2: 观察Scheduler → PassCtrl → NoC FSM状态
Step 3: 定位哪个NoC通道卡住（ifmap/filter/ipsum/opsum）
Step 4: 深入卡住的通道，观察index_generator → mapper → tag_generator → GIN路径
Step 5: 修复死锁

## 层次化路径速查

```
DUT.SCHEDULER.state_crnt          — 调度器FSM状态
DUT.PROCESSING.nocs_top_inst.pass_controller_inst.state_crnt  — PassCtrl
DUT.PROCESSING.nocs_top_inst.noc_controller_inst.ifmap_noc_inst.done
DUT.GLB.U1_IFMAP.U0_0.mem[index]  — IFMAP GLB bank 0
DUT.GLB.U2_FILTER.U0_0.mem[index] — FILTER GLB bank 0
DUT.GLB.U3_BIAS.U0_0.mem[index]   — BIAS GLB bank 0
```

## 编译命令

```bash
V=E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin
cd H:/moateff_trace/debug_campaign

$V/xvlog -sv \
  H:/moateff_test/src/EYERISS.sv H:/moateff_test/src/scheduler.sv \
  "H:/moateff_test/src/GLB UNIT/"*.sv "H:/moateff_test/src/GLB UNIT/"*.v \
  H:/moateff_test/src/PE Array/processing_unit.sv \
  "H:/moateff_test/src/PE Array/Processing Element/"*.sv "H:/moateff_test/src/PE Array/Processing Element/"*.v \
  "H:/moateff_test/src/PE Array/Network on Chip/"*.sv \
  "H:/moateff_test/src/PE Array/Network on Chip/Network on Chip Controller/"*.sv \
  "H:/moateff_test/src/PE Array/Sync FIFO/"*.v \
  "H:/moateff_test/src/RelU/"*.sv "H:/moateff_test/src/SCAN CHAIN/"*.sv \
  "H:/moateff_test/src/INTERFACE UNIT/"*.sv \
  H:/moateff_test/sim/shared_pkg.sv H:/moateff_test/sim/cfg_pkg.sv \
  tb/tb_debug_step1.sv

$V/xelab -timescale 1ns/1ps -L xil_defaultlib -s step1_sim tb_debug_step1
$V/xsim step1_sim -R
```
