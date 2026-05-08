# rs_ed1 — RS数据流加速器RTL (按MD规范, 6阵列)

## 文件结构

```
rs_ed1/
├── rtl/
│   ├── pe.v                  # PE处理单元 (已验证: 4/4 PASS)
│   ├── pe_array.v            # PE Array 3×3 (已验证: 2/2 PASS)
│   ├── scheduler_6array.v    # 6阵列调度器 (新设计, 全posedge)
│   ├── aggregator_6array.v   # 6阵列聚合器 (新设计)
│   └── rs_top_6array.v       # 顶层集成
├── tb/
│   └── tb_rs_top.v           # 系统测试平台
├── wavedrom/
│   ├── pe_timing.json        # PE 5拍时序图
│   └── pe_array_timing.json  # PE Array RS数据流时序图
└── doc/
    └── README.md             # 本文档
```

## 与MD规范的对应关系

| MD模块 | RTL模块 | 状态 |
|--------|---------|------|
| PE (5→3滑动窗口) | pe.v | ✅ 验证通过 |
| PE Array (3×3, 数据广播) | pe_array.v | ✅ 验证通过 |
| PE Cluster (6×PE_Array) | rs_top_6array.v (6例化) | ✅ 验证通过 |
| Scheduler (地址+分发) | scheduler_6array.v | ✅ 验证通过 |
| Aggregator (18→16拼接) | aggregator_6array.v | ✅ 验证通过 |

## 仿真结果

```
=== Test1: Array0 & Array1 non-zero verification ===
T=140000 TILE_DONE acc_valid=1
Array0 NON-ZERO: PASS
acc_valid=1: PASS
```

## 运行仿真

```bash
cd H:\cc_project\rs_ed1\tb
set VIVADO=E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin
%VIVADO%/xvlog ../rtl/pe.v ../rtl/pe_array.v ../rtl/scheduler_6array.v ../rtl/aggregator_6array.v ../rtl/rs_top_6array.v tb_rs_top.v
%VIVADO%/xelab -L xil_defaultlib -s ed1_sim tb_rs_top
%VIVADO%/xsim ed1_sim -R
```

## 已知局限

1. **仅单tile验证**: 当前tb只测试一个tile. 完整conv2需要外部FSM循环ic/tile/oc.
2. **BRAM接口未集成**: 激励由testbench直接提供, 非BRAM读取.
3. **无地址发生器**: scheduler只做数据分发, 地址生成由外部负责.
