# Debug Campaign Status — 2026-05-12

## 已完成

| # | 项目 | 结果 |
|---|------|------|
| 1 | 调试工作空间建立 | `H:/moateff_trace/debug_campaign/` |
| 2 | GLB后门写入验证 | 编译通过，层次路径确认正确 |
| 3 | 扫描链cfg_scan_chain可用 | proven by tb_smoke |
| 4 | 内部信号探针 | 编译通过: Scheduler.state_crnt, PassCtrl.state_crnt, NoC done signals |
| 5 | AlexNet Conv1权重+数据+Golden Reference | `H:/moateff_trace/alxnet_training/` |

## 当前阻塞

**全系统xsim仿真速度**: 168 PE阵列 + posedge/negedge双沿 + 全NoC逻辑。仿真中每个周期都需评估大量事件。扫描链3644 bits的加载在仿真中非常缓慢。

v2 testbench (`tb/tb_debug_v2.sv`) 正在后台运行中，5000周期监控。

## 下一步

1. 如果v2跑通：观察NoC FSM状态，定位死锁通道
2. 如果v2超时：改为代码审阅方式分析NoC死锁
3. 考虑使用Verilator加速仿真（>100x faster than xsim）
