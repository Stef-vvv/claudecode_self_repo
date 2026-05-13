# moateff_revise_comparison/ — 目录介绍

> 用途：记录对原始 RTL 源码的**所有修改**及其原因。极小目录，只有 1 个文件。

---

## 文件清单

### `CHANGES.md`
**内容**: 4 项接口级修改的详细清单

| # | 文件 | 修改位置 | 原始 | 修改后 | 原因 |
|---|------|---------|------|--------|------|
| 1 | EYERISS.sv | L231-233 | scan_chain 例化端口 `.se(sc_se)`, `.si(sc_si)`, `.so(sc_so)` | `.scan_en(sc_se)`, `.scan_in(sc_si)`, `.scan_out(sc_so)` | scan_chain.sv 模块端口名在最终版已改为 scan_en/scan_in/scan_out，但顶层例化用的还是旧名 se/si/so |
| 2 | EYERISS.sv | L465-468 | glb_unit 例化参数 `.DEPTH_IFMAP()`, `.DEPTH_FILTER()`, `.DEPTH_PSUM()`, `.DEPTH_BIAS()` | `.IFMAP_GLB_DEPTH()`, `.FILTER_GLB_DEPTH()`, `.PSUM_GLB_DEPTH()`, `.BIAS_GLB_DEPTH()` | glb_unit.sv 的参数名在最终版已改为 XXX_GLB_DEPTH，但顶层传参用的还是旧名 DEPTH_XXX |
| 3 | cfg_pkg.sv | 5 处 | `D:/data/...` 绝对路径 | `H:/moateff_test/...` 绝对路径 | 作者原路径指向 D 盘，不适用于当前机器环境 |
| 4 | file_pkg.sv | 1 处 | `.../log.txt` 输出路径 | `H:/moateff_test/sim/log.txt` | 同上，适配本地路径 |

**关键说明**:
- 所有 4 项修改都是**接口/路径适配**，没有任何功能逻辑改动
- 修改后 71 RTL 文件在 Vivado 2020.2 下零语法错误通过编译
- 这些修改说明原始代码的模块内部实现没有问题，只是顶层连接和路径需要适配

---

## 使用说明
- 这是**最小修改原则**的记录：只改必要的接口/路径，不改功能
- 如果要在其他机器上运行，需要类似地修改 cfg_pkg.sv 和 file_pkg.sv 的路径
