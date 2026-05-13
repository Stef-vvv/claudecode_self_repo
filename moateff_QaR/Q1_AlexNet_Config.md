# Q1: 是否必须跑AlexNet结构？

## 问题

配置是预计算好的（论文只给了AlexNet配置），我们要跑就必须跑AlexNet结构吗？

## 回答

**不必须，但有两条路径可选。**

### 路径A: 跑AlexNet（论文原路径）

优点:
- 配置文件和参数已就绪 (`config/conv1/` ~ `config/conv5/`)
- 与论文JSSC 2017 Table III完全对应
- 可复现论文结果
- `shared_pkg.sv` 中已定义5层Conv参数

需要补充的:
- AlexNet预训练权重（需从PyTorch提取并量化为Q3.13）→ 见 `H:/moateff_trace/02_ALEXNET_WEIGHTS.md`
- 输入图片（可用`model/utils/jpeg_to_Q3.13_txt.py` + `test_segements_4conv.py`生成）
- 大容量GLB数据加载（ifmap 227×227×3 ≈ 150K值, filter CONV1 11×11×3×96 ≈ 35K值）

### 路径B: 自定义小层（已验证可工作）

优点:
- 配置灵活，可用 `config_script.py` 生成任意层的配置
- 已在8×8×1层上验证过scan chain加载（3644 bits vs Conv1的10935 bits）
- 数据量小，便于调试（64个ifmap值 vs 150K）
- 可用Python行为模型 `py/eyeriss_model.py` 生成golden reference

做法:
1. 编辑 `config_script.py` 中的层参数 (H, W, R, S, E, F, C, M, N, U, m, n, e, p, q, r, t)
2. 运行生成 `enables.txt`, `serial_data.txt` 等配置文件
3. 用 `py/gen_test_data.py` 生成测试数据
4. 编译仿真，对比结果

### 推荐

**先路径B验证硬件正确性，再路径A复现论文。** 这符合"先简化验证，再完整测试"的工程方法。小层跑通后，将同一套流程放大到AlexNet Conv1即可。

## 技术背景

`config_script.py` 的配置生成逻辑:
- 读取 `parameters.txt` → 生成17个参数寄存器位
- 读取 `enables.txt` → 生成168-bit PE使能矩阵
- 读取 `ifmap_ids.txt` 等 → 生成NoC路由ID
- 将所有位反转 → 写入 `serial_data.txt`

因此任何层只要提供正确的参数和映射配置，就能生成有效的scan chain位流。不限于AlexNet。
