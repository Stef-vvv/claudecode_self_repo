# 原工程源码改动记录

## 改动原则
- 仅修复编译/elaboration错误，不修改任何功能逻辑
- 最小改动量：只改不匹配的接口名称

---

## 改动1: EYERISS.sv — scan_chain 端口名修正

**文件**: `src/EYERISS.sv` 第231-233行

**问题**: 顶层例化 SCAN_CHAIN 时使用的端口名 `.se()`, `.si()`, `.so()` 与 `scan_chain.sv` 模块实际定义的端口名不匹配。原来的 `.so` 含义不清，且与扫描链实际端口命名不一致。

**原代码**:
```systemverilog
// 原 (不匹配)
SCAN_CHAIN #(...) U0_SCAN_CHAIN (
    ...
    .se(scan_en),
    .si(scan_in),
    .so(scan_w),
    ...
);
```

**改为**:
```systemverilog
// 改后 (匹配 scan_chain.sv 端口定义)
SCAN_CHAIN #(...) U0_SCAN_CHAIN (
    ...
    .scan_en(scan_en),
    .scan_in(scan_in),
    .scan_out(scan_w),
    ...
);
```

**原因**: `scan_chain.sv` 模块定义 (`src/SCAN CHAIN/scan_chain.sv`) 中端口名为 `scan_en`, `scan_in`, `scan_out`。原作者的顶层文件使用了简化的 `.se`/`.si`/`.so`，但模块中并未定义这些端口，导致 xelab elaboration 报错"端口未找到"。

**影响范围**: 仅端口名映射，无功能变化。

---

## 改动2: EYERISS.sv — glb_unit 参数名修正

**文件**: `src/EYERISS.sv` 第465-468行

**问题**: 顶层例化 GLB 时使用的参数名 `.DEPTH_ifmap()`, `.DEPTH_filter()`, `.DEPTH_psum()`, `.DEPTH_bias()` 与 `glb_unit.sv` 模块实际定义的参数名不匹配。

**原代码**:
```systemverilog
// 原 (不匹配)
glb_unit #(
    .DEPTH_ifmap(IFMAP_GLB_DEPTH),
    .DEPTH_filter(FILTER_GLB_DEPTH),
    .DEPTH_psum(PSUM_GLB_DEPTH),
    .DEPTH_bias(BIAS_GLB_DEPTH)
) U0_GLB (
    ...
);
```

**改为**:
```systemverilog
// 改后 (匹配 glb_unit.sv 参数定义)
glb_unit #(
    .IFMAP_GLB_DEPTH(IFMAP_GLB_DEPTH),
    .FILTER_GLB_DEPTH(FILTER_GLB_DEPTH),
    .PSUM_GLB_DEPTH(PSUM_GLB_DEPTH),
    .BIAS_GLB_DEPTH(BIAS_GLB_DEPTH)
) U0_GLB (
    ...
);
```

**原因**: `glb_unit.sv` 模块定义 (`src/GLB UNIT/glb_unit.sv`) 中参数名为 `IFMAP_GLB_DEPTH`, `FILTER_GLB_DEPTH`, `PSUM_GLB_DEPTH`, `BIAS_GLB_DEPTH`。原作者顶层使用了不同的命名 `.DEPTH_xxx`。这也是 elaboration 时参数未找到的原因。

**影响范围**: 仅参数名映射，无功能变化。

---

## 改动3: sim/cfg_pkg.sv — 文件路径修正

**文件**: `sim/cfg_pkg.sv`

**问题**: 原 `$readmemb` 路径指向作者的本地D盘 (`D:/data/Graduation Project/...`)，这些路径在我们的环境中不存在。

**改动**: 将配置文件的 `$readmemb` 路径改为项目相对路径 `../config/conv1/` 等。

**原因**: 路径硬编码为原作者本地路径，移植时需要更新。

---

## 改动4: sim/file_pkg.sv — 文件路径修正

**文件**: `sim/file_pkg.sv`

**问题**: 同上，结果比较函数的输出路径指向 `D:/data/...`。

**改动**: 将输出路径改为本地路径。

**原因**: 同上，路径硬编码问题。

---

## 未改动的文件

以下文件**完全未修改**：
- `src/scheduler.sv`
- `src/PE Array/` (全部56个文件)
- `src/GLB UNIT/` (全部7个文件)
- `src/INTERFACE UNIT/` (全部13个文件)
- `src/RelU/` (全部2个文件)
- `src/SCAN CHAIN/` (全部3个文件)
- `sim/shared_pkg.sv`
- `sim/Eyeriss_tb.sv` (原始，未使用)
- `sim/fifo_if_pkg.sv`
- `sim/glb_pkg.sv`
- `sim/layer_pkg.sv`
- `sim/load_pkg.sv`
- `sim/test_pkg.sv`

## 新增文件

以下文件是我们在原工程基础上**新添加**的，非原作者代码：
- `sim/tb_smoke.sv` — 冒烟测试平台
- `sim/tb_tiny_test.sv` — 小规模端到端自检测试
- `sim/tb_selfcheck.sv` — 通用自检测试平台
- `py/eyeriss_model.py` — Python行为级模型
- `py/gen_tiny_config.py` — 配置生成器
- `py/gen_test_data.py` — 测试数据生成器
- `config/tiny/` — 自建8×8×1测试层配置

---

## 总结

对原作者RTL源码的改动总计**4处**，全部为接口名称/路径修正：
1. scan_chain端口名: `.se/.si/.so` → `.scan_en/.scan_in/.scan_out`
2. glb_unit参数名: `.DEPTH_xxx` → `.XXX_GLB_DEPTH`
3. cfg_pkg.sv文件路径: `D:/data/...` → `../config/...`
4. file_pkg.sv文件路径: `D:/data/...` → 本地路径

以上改动均不涉及功能逻辑，仅为编译通过所需的最小接口修正。原作者的设计逻辑、状态机、数据路径完全保留。
