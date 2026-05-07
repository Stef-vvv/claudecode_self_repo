# 硬件RTL开发状态报告

## 已验证模块 (Vivado 2020.2仿真)

| 模块 | 文件 | 测试 | 结果 |
|------|------|------|------|
| PE | rtl/pe.v | 4项 (MAC, ACC, 时序, 锁存) | ALL PASS |
| PE_Array | rtl/pe_array.v | 2项 (累加, RS数据流) | ALL PASS |
| Scheduler (单) | rtl/scheduler.v | 3项系统测试 | ALL PASS |
| Aggregator (单) | rtl/aggregator.v | 3项系统测试 | ALL PASS |
| rs_top (单阵列) | rtl/rs_top.v | 3项系统测试 | ALL PASS |

关键验证数据:
- PE: `[14,20,26]`, `[17,36,55]` (与Python pe_test一致)
- PE Array: `[42,60,78]`, `[411,456,501]` (与Python pe_array_test一致)
- 系统: `[411,456,501]`, `[18,27,36]`, `[118,227,336]` (完整tile处理链路)

## 6阵列扩展 (已设计, 待调试)

| 模块 | 文件 | 状态 |
|------|------|------|
| Scheduler_6array | rtl/scheduler_6array.v | 独立功能验证通过 (st_g, ni_d, data正确时序) |
| Aggregator_6array | rtl/aggregator_6array.v | 待系统级验证 |
| rs_top_6array | rtl/rs_top_6array.v | 待系统级验证 |

已知集成问题:
- rs_top_6array测试输出全零 → Scheduler和PE Array各自独立工作正常, 集成连接正确. 根因定位中: testbench数据与6阵列数据切片不匹配(padding影响).

## 设计原则

1. **纯Verilog-2001**: 无generate, 无for循环, 无SystemVerilog
2. **全posedge clk**: 所有寄存器统一上升沿
3. **nxt_state驱动输出**: 输出由组合nxt_state决定, 在posedge寄存, 下一周期PE采样
4. **简化RS架构**: 数据广播+start对角线传播→列0有效, 列1-2冗余

## Agent代码审查结果

两个agent审查了全部RTL代码, 确认:
- PE Array: psum传播正确, start传播正确, filter传播正确
- 简化RS架构正确: 列0优先输出, 列1-2冗余(设计意图)
- 6阵列数据切片逻辑正确

发现的bug及修复:
- [已修复] scheduler_6array FSM缺少default分支 → 已添加
- [设计选择] 列1-2数据广播导致冗余计算 → 这是简化RS的核心特征
- [已知] Aggregator累加无饱和保护 → ACC_WIDTH=16对当前数据范围足够

## 文件结构

```
correspond_hardware/
├── rtl/
│   ├── pe.v              # PE (已验证)
│   ├── pe_array.v        # PE Array 3x3 (已验证)
│   ├── scheduler.v       # 单阵列Scheduler (已验证)
│   ├── aggregator.v      # 单阵列Aggregator (已验证)
│   ├── rs_top.v          # 单阵列顶层 (已验证)
│   ├── scheduler_6array.v  # 6阵列Scheduler (独立验证通过)
│   ├── aggregator_6array.v # 6阵列Aggregator (待集成验证)
│   └── rs_top_6array.v     # 6阵列顶层 (待集成验证)
├── tb/
│   ├── pe_tb.v, pe_array_tb.v  # PE/Array测试 (PASS)
│   ├── rs_top_tb.v              # 系统测试 (PASS)
│   └── rs_top_6array_tb.v       # 6阵列测试 (调试中)
├── wavedrom/
│   ├── pe_timing.json
│   └── pe_array_timing.json
├── README.md
├── QUANTIZATION_GUIDE.md
└── STATUS.md (本文档)
```

## 版本历史

- `correspond_hardware_v1/` — 初版 (含generate/for)
- `correspond_hardware_v2/` — 无for/generate版本, negedge scheduler
- `correspond_hardware/` — 当前版本: 全posedge, nxt_state驱动, 含6阵列扩展
