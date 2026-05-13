# 文件说明与使用指南

## 原始作者文件结构

原始项目来自 `H:/complete_version/moateff/2025_11_1_Eyeriss-v1-main/`。

### 可直接使用的文件

| 目录/文件 | 用途 | 状态 |
|-----------|------|------|
| `src/` (全部71文件) | RTL硬件设计 | 编译通过, 零错误 |
| `config/conv1/` ~ `conv5/` | AlexNet 5层配置 | 完整可用 |
| `config/config_script.py` | 配置生成脚本 | 可用 |
| `sim/shared_pkg.sv` | 参数定义包 | 完整 |
| `sim/cfg_pkg.sv` | scan chain加载 | 路径已修复 |
| `sim/fifo_if_pkg.sv` | GLB数据加载task | 完整(底层) |
| `sim/file_pkg.sv` | 结果比较task | 路径已修复 |

### 原作者未完成的部分

| 文件 | 问题 |
|------|------|
| `sim/load_pkg.sv` | 数据加载task全部注释, 引用的数据文件不存在 |
| `sim/layer_pkg.sv` | run_conv1()不加载数据, run_conv2~5只有空壳 |
| `sim/test_pkg.sv` | 只调用run_conv1, conv2-5注释 |
| `sim/glb_pkg.sv` | 全部注释(GLBDebug) |
| `sim/Eyeriss_tb.sv` | 调用run_test()无数据加载 |
| `model/` (Python) | 交互式脚本,需用户提供输入文件 |

### 缺失的外部文件

| 预期路径 | 说明 |
|----------|------|
| `D:/data/Graduation Project/GP_AlexNet/Results/Conv1/ifmap/conv1_ifmap_seg*.txt` | 8段ifmap数据 |
| `D:/data/.../Conv1/filter/conv1_filter_64.txt` | 滤波器数据 |
| `D:/data/.../Conv1/bias/conv1_bias_64.txt` | 偏置数据 |
| `D:/data/.../Conv2~5/` | 其余4层数据 |

## model/ 目录中的Python脚本

`H:/complete_version/moateff/2025_11_1_Eyeriss-v1-main/model/`

| 脚本 | 功能 | 输入 | 输出 |
|------|------|------|------|
| `from_resize_to_pooling_colored.py` | 完整流水线: resize→conv→relu→pool | 用户指定图片路径 | 各阶段.txt + .jpg |
| `from_resize_to_pooling_gray.py` | 同上, 灰度版本 | 图片路径 | .txt + .jpg |
| `scripts/convolution.py` | 单步2D卷积 (Q3.13) | ifmap.txt + weights.txt + biases.txt | conv_output.txt |
| `scripts/relu.py` | ReLU激活 | conv_output.txt | relu_output.txt |
| `scripts/pooling.py` | Max Pooling (3×3, stride 2) | 前一阶段输出.txt | maxpool_output.txt |
| `scripts/padding.py` | Zero padding | 输入文件 | padding_output.txt |
| `scripts/resize.py` | 图像缩放至227×227 | JPEG图片 | Q3.13 .txt |
| `scripts/conv.py` | 交互式卷积 | 用户指定路径 | 用户指定路径 |
| `utils/jpeg_to_Q3.13_txt.py` | JPEG→Q3.13转换 | JPEG文件 | .txt文件 |
| `utils/merge_split.py` | 16-bit↔64-bit格式转换 | .txt文件 | .txt文件 |
| `utils/ifmap_segmentation.py` | ifmap分段 (适配8段加载) | 完整ifmap.txt | 8×segment.txt |
| `utils/diff.py` | 两文件逐行比较 | file1.txt file2.txt | 差异报告 |

### 数据格式
- 所有数据使用 Q3.13 定点: 16-bit有符号, step=1/8192
- 存储格式: 每行一个二进制字符串 (如 `0000000100000000`)
- 64-bit打包: 4个16-bit值拼接为一行

## 本项目新增文件

| 文件 | 用途 |
|------|------|
| `py/eyeriss_model.py` | 周期精确行为模型 (Scheduler+NoC+PE+GLB) |
| `py/gen_tiny_config.py` | 任意层scan chain配置生成器 |
| `py/gen_test_data.py` | Q3.13测试数据+golden reference生成 |
| `sim/tb_smoke.sv` | 冒烟测试 (验证scheduler FSM) |
| `sim/tb_tiny_test.sv` | 小规模端到端自检测试 |
| `sim/tb_selfcheck.sv` | 通用自检测试平台 |
| `config/tiny/` | 自建8×8×1测试层配置 |
| `test_data/` | 生成的测试数据文件 |
| `docs/ARCHITECTURE.md` | 硬件架构详细文档 |
| `docs/BEHAVIORAL_MODEL.md` | Python行为模型使用说明 |
| `docs/FILE_GUIDE.md` | 本文件 |
| `PROGRESS.md` | 验证进度与问题记录 |
| `README.md` | 项目总览 |

## 编译运行命令

### 环境
- Vivado 2020.2: `E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin`
- Python 3.x (numpy)

### 编译全部RTL
```bash
cd H:/moateff_test
bash compile.sh
```

### 运行冒烟测试
```bash
V="E:/VIVADO_Download/VIVADO/Vivado/2020.2/bin"
$V/xvlog -sv sim/tb_smoke.sv
$V/xelab -timescale 1ns/1ps -L xil_defaultlib -s smoke_sim tb_smoke
$V/xsim smoke_sim -R
```

### 运行Python行为模型
```bash
python py/eyeriss_model.py
```

### 生成自定义层配置
```bash
python py/gen_tiny_config.py    # 编辑脚本修改层参数
```

### 生成测试数据
```bash
python py/gen_test_data.py      # 编辑脚本修改数据
```
