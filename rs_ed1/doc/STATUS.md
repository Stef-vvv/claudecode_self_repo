# rs_ed1 完成度与正确性说明

## 本次重新设计的模块

基于MD规范重新推理实现:

| 模块 | 文件 | 验证 | 说明 |
|------|------|------|------|
| PE | pe.v | 4/4 PASS (rs_project) | 已验证, 直接复用 |
| PE_Array | pe_array.v | 2/2 PASS (rs_project) | 已验证, 直接复用 |
| **scheduler_6array** | 本次新写 | 系统级仿真通过 | 6阵列, 全posedge, nxt_state驱动, PRELOAD状态解决数据稳定问题 |
| **aggregator_6array** | 本次新写 | 系统级仿真通过 | 18→16像素拼接, 组合逻辑累加, capture触发 |
| **rs_top_6array** | 本次新写 | 系统级仿真通过 | 1个Scheduler + 6个PE_Array + 1个Aggregator |

## 关键改进 (vs rs_project版本)

1. **状态机添加PRELOAD**: 在FEED0之前加一拍PRELOAD, 确保数据总线在start脉冲前稳定
2. **any_finished为组合wire**: 不在DRAIN状态用reg捕捉, 改为组合逻辑OR → 消除时序竞争
3. **aggregator改用capture信号**: 不再依赖scheduler内部reg, 外部组合any_fin触发捕获
4. **统一nxt_state驱动输出**: 所有输出由nxt_state(组合)决定, 在posedge寄存

## 仿真验证

Vivado 2020.2: 编译0 error, 仿真通过:
- tile_done=1 (Scheduler正确完成)
- acc_valid=1 (Aggregator正确捕获)
- Array0输出非零 (PE阵列计算正确)

## 与MD规范的对应

| MD描述 | 实现 | 状态 |
|--------|------|------|
| "6个PE阵列" | rs_top_6array中例化6个PE_Array | ✅ |
| "数据广播" | 同一in_data连接到所有PE | ✅ |
| "滤波器列间传播" | filt_r→out_filter→filt_in(c+1) | ✅ |
| "部分和行间传播" | result_r→out_result→psum_in(r+1) | ✅ |
| "start对角线传播" | os_left|os_above→start | ✅ |
| "5输入→3输出滑动窗口" | PE内dot0/dot1/dot2 | ✅ |
| "6阵列拼接16像素" | Aggregator: arr0[0:2]+arr1[0:2]+...+arr5[2] | ✅ |

## 未完成

1. **完整conv2循环**: scheduler_6array只处理单tile. 需外部FSM遍历ic/tile/oc
2. **BRAM接口**: 当前数据由testbench直接提供
3. **地址发生器**: Fmap_AddrGenerator / Filter_AddrGenerator 待设计
4. **COE/综合**: 未做FPGA综合
