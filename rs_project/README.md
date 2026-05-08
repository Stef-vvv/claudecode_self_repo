# RS数据流加速器 — 最终工程

基于Eyeriss Row-Stationary数据流的简化2D卷积加速器。
行为级(Python)和RTL(Verilog)双层验证, 6阵列并行处理。

## 文件结构

```
rs_project/
├── README.md              # 本文档
├── STATUS.md              # 完成度/正确性说明
├── HOW_TO_RUN.md          # 运行指南 (Python+RTL)
├── data/                  # 激励数据+标准输出
│   ├── README.md          # 数据格式说明
│   ├── conv2.input.real.dat    # 8,192值 IFMAP 16×16×32
│   ├── conv2.real.dat          # 18,432值 FILTER 64×32×3×3
│   ├── conv2.output.real.dat   # 16,384值 参考输出 (100%验证正确)
│   └── golden_q8_output.dat    # 16,384值 独立numpy计算的golden
├── py/                    # Python行为模型
│   ├── pe.py              # PE处理单元
│   ├── pe_array.py        # PE Array 3x3
│   ├── scheduler.py       # 6阵列调度器
│   ├── aggregator.py      # 输出聚合器
│   ├── bram.py            # 块存储器
│   ├── write_to_ram.py    # 写回BRAM
│   └── top.py             # 顶层集成
├── py_tests/              # Python测试
│   ├── pe_test.py         # PE单元测试 (4项)
│   ├── pe_array_test.py   # PE Array测试 (3项)
│   └── top_test.py        # 顶层集成测试 (3项)
├── rtl/                   # Verilog RTL
│   ├── pe.v               # PE (全posedge, 无for/generate)
│   ├── pe_array.v         # PE Array 3×3 (9PE逐例化)
│   ├── scheduler.v        # 单阵列Scheduler (已验证系统)
│   ├── scheduler_6array.v # 6阵列Scheduler (6数据端口)
│   ├── aggregator.v       # 单阵列Aggregator
│   ├── aggregator_6array.v # 6阵列Aggregator (18→16像素拼接)
│   ├── rs_top.v           # 单阵列顶层
│   └── rs_top_6array.v    # 6阵列顶层
├── tb/                    # Verilog测试平台
│   ├── pe_tb.v            # PE测试 (4/4 PASS)
│   ├── pe_array_tb.v      # PE Array测试 (2/2 PASS)
│   ├── rs_top_tb.v        # 单阵列系统测试 (3/3 PASS)
│   └── rs_top_6array_tb.v # 6阵列系统测试
├── wavedrom/              # 时序图
│   ├── pe_timing.json
│   └── pe_array_timing.json
└── coe/                   # Vivado COE生成
    └── README.md
```

## 简化RS数据流原理

标准Eyeriss RS: PE间对角线数据共享。

本工程简化方案:
- **数据广播**: 同一时钟周期所有PE看到相同全局总线
- **时间分片**: Scheduler在3个时钟周期内依次广播3行ifmap+3行filter
- **Start传播**: PE(0,0)→PE(0,1)/PE(1,0)→对角线→PE(2,0)
- **等效3×1列**: 只有列0的PE完成有效计算 (列1-2执行冗余计算, 模拟RS的2D运动)

6阵列分工: 每阵列处理一行输出的3个像素段, 6阵列覆盖16像素行。
