# Q3: GLB Banks — 25 in paper vs 4 in RTL?

## 1. RTL GLB Structure: How Many Bank Instances?

### Top level (`glb_unit.sv`, line 62-163)

`glb_unit` instantiates exactly **4 logical GLB modules**:

| Instance | Module | Lines |
|----------|--------|-------|
| U1_IFMAP | ifmap_glb | 72-92 |
| U2_FILTER | filter_glb | 95-115 |
| U3_BIAS | bias_glb | 118-138 |
| U4_PSUM | psum_glb | 141-161 |

### Each `*_glb` internally has **4 `dual_bram` instances**

Every `ifmap_glb`, `filter_glb`, `bias_glb`, `psum_glb` is structurally identical: 4 instances of `dual_bram` named `U0_0`, `U0_1`, `U1_0`, `U1_1`. This is for **width packing**: port A is 64-bit (written from DRAM via FIFO), port B is 16-bit (read by NoC/PE array). The 4 BRAMs each store a 16-bit slice of the 64-bit word, using `addr[ADDR_WIDTH-1:2]` for the common upper address bits and `addr[1:0]` to select which BRAM on port B read.

**Total physical BRAM count = 4 GLB types x 4 dual_bram = 16 BRAMs**

### Each `dual_bram` (`dual_bram.sv`)

A true dual-port RAM with `(* ram_style = "block" *)` attribute (maps to FPGA BRAM or ASIC SRAM). Data width = 16 bits. Depth = MEM_DEPTH/4 (e.g., IFMAP_GLB_DEPTH=7945 -> each dual_bram depth = 7945/4 = 1987 entries).

Port A: 16-bit write/read. Port B: 16-bit write/read. Both operate on `negedge clk`.

## 2. Paper (Eyeriss JSSC 2017): GLB Description

The paper describes the Global Buffer as:
- **25 banks** of **512 x 64-bit** SRAM
- Each bank: 512 deep, 64 bits wide = 512 x 8 bytes = 4 KB per bank
- Total GLB capacity: 25 x 4 KB = **100 KB** (102,400 bytes)
- Banks can be **reconfigured** at compile time between ifmap and psum storage
- Filter weights are stored in a separate dedicated memory (not in the 25 GLB banks)
- A centralized NoC connects GLB banks to the PE array

## 3. Comparison: Paper vs RTL

| Aspect | Paper (JSSC 2017) | RTL (`moateff_test`) |
|--------|-------------------|----------------------|
| **Physical banks** | 25 SRAM macros (512x64 each) | 16 BRAM instances (variable depth x 16-bit) |
| **Logical organization** | 25 banks, configurable assignment | 4 fixed-type GLBs (ifmap/filter/bias/psum) |
| **Reconfigurable?** | Yes: banks assigned to ifmap OR psum at compile time | **No**: assignment is hard-wired (4 separate modules) |
| **Filter storage** | Separate dedicated memory | Integrated as `filter_glb` (one of the 4 GLBs) |
| **Total capacity** | 100 KB fixed | Variable, set by parameters (see Q6) |
| **Word width (internal)** | 64-bit per bank | 64-bit on port A (DRAM side), 16-bit on port B (PE side) |
| **Architecture** | Unified pool of banks, routed via NoC | Dedicated buffers per data type |

## 4. Is the RTL a Simplification?

**Yes, the RTL is a simplification with a different architecture choice:**

1. **Fixed assignment instead of reconfigurable banks**: The paper uses a pool of 25 identical banks that can be dynamically (at compile time) partitioned between ifmap and psum. The RTL has 4 dedicated, hard-wired buffers — one per data type. This is architecturally simpler but less flexible.

2. **Filter weights in GLB instead of separate memory**: The paper has separate storage for filter weights. The RTL includes `filter_glb` as one of the 4 GLBs.

3. **Width packing via 4 BRAMs instead of native 64-bit SRAM**: The paper's banks are natively 64-bit wide. The RTL achieves 64-bit access by ganging 4 x 16-bit BRAMs together, using address bit-steering to read individual 16-bit values on port B.

4. **16 vs 25 physical macros**: The RTL uses 16 BRAMs total vs. the paper's 25. The paper's total capacity (100 KB) is a fixed hardware parameter; the RTL's capacity is configurable via Verilog parameters.

## 5. Where is "Reconfigurable Bank Assignment" in the RTL?

**It does not exist in this RTL.** There is no mechanism to reassign memory banks between ifmap and psum at runtime or compile time. The four GLB types are instantiated as separate, independent modules with fixed roles:

```verilog
// glb_unit.sv: fixed, hard-wired instances
ifmap_glb  #(...) U1_IFMAP (...);
filter_glb #(...) U2_FILTER (...);
bias_glb   #(...) U3_BIAS (...);
psum_glb   #(...) U4_PSUM (...);
```

The paper's reconfigurability (e.g., allocating more banks to psum for layers with large partial sums) is not implemented. The RTL's approach is a **static partitioning** design choice for a research/educational implementation.

## 6. GLB Depth Parameters (`shared_pkg.sv`, lines 182-185)

```systemverilog
parameter IFMAP_GLB_DEPTH  = 7945;
parameter FILTER_GLB_DEPTH = 3872;
parameter PSUM_GLB_DEPTH   = 46656;
parameter BIAS_GLB_DEPTH   = 64;
```

These are the **logical depths** in units of 16-bit entries. See Q6 for the derivation of each value.














































**第三季度问题：GLB Banks — 论文中的25个 vs RTL中的4个？**

**1. RTL GLB结构：有多少个Bank实例？**

**顶层（`glb_unit.sv`，第62-163行）**

`glb_unit` 精确地例化了 **4个逻辑GLB模块**：

| 实例 | 模块 | 行号 |
|---|---|---|
| U1_IFMAP | ifmap_glb | 72-92 |
| U2_FILTER | filter_glb | 95-115 |
| U3_BIAS | bias_glb | 118-138 |
| U4_PSUM | psum_glb | 141-161 |

**每个 `*_glb` 内部有 **4个 `dual_bram` 实例****

每个 `ifmap_glb`、`filter_glb`、`bias_glb`、`psum_glb` 在结构上完全相同：4个 `dual_bram` 实例，命名为 `U0_0`、`U0_1`、`U1_0`、`U1_1`。这是为了 **位宽打包**：端口A是64位的（通过FIFO从DRAM写入），端口B是16位的（由NoC/PE阵列读取）。这4个BRAM各自存储64位字的一个16位切片，使用 `addr[ADDR_WIDTH-1:2]` 作为公共的高位地址位，并在端口B读取时使用 `addr[1:0]` 来选择哪个BRAM。

**物理BRAM总数 = 4种GLB类型 x 4个 dual_bram = 16个BRAM**

**每个 `dual_bram`（`dual_bram.sv`）**

一个带有 `(* ram_style = "block" *)` 属性的真双端口RAM（映射到FPGA BRAM或ASIC SRAM）。数据宽度 = 16位。深度 = MEM_DEPTH/4（例如，IFMAP_GLB_DEPTH=7945 -> 每个dual_bram深度 = 7945/4 = 1987个条目）。

端口A：16位写/读。端口B：16位写/读。两者都在 `negedge clk` 上操作。

**2. 论文（Eyeriss JSSC 2017）：GLB描述**

论文将全局缓冲区描述为：
-   **25个bank**，每个 **512 x 64位** SRAM
-   每个bank：512深度，64位宽 = 512 x 8字节 = 每个bank 4 KB
-   GLB总容量：25 x 4 KB = **100 KB**（102,400字节）
-   Bank可以在编译时在ifmap和psum存储之间进行 **重配置**
-   滤波器权重存储在一个独立的专用存储器中（不在25个GLB bank中）
-   一个集中式的NoC将GLB bank连接到PE阵列

**3. 对比：论文 vs RTL**

| 方面 | 论文（JSSC 2017） | RTL（`moateff_test`） |
|---|---|---|
| **物理bank** | 25个SRAM宏（每个512x64） | 16个BRAM实例（可变深度 x 16位） |
| **逻辑组织** | 25个bank，可配置分配 | 4个固定类型的GLB（ifmap/filter/bias/psum） |
| **可重配置？** | 是：bank在编译时分配给ifmap或psum | **否**：分配是硬连线的（4个独立模块） |
| **滤波器存储** | 独立的专用存储器 | 集成为 `filter_glb`（4个GLB之一） |
| **总容量** | 固定100 KB | 可变，由参数设置（见Q6） |
| **字宽（内部）** | 每个bank 64位 | 端口A（DRAM侧）64位，端口B（PE侧）16位 |
| **架构** | 统一的bank池，通过NoC路由 | 每种数据类型的专用缓冲区 |

**4. RTL是一种简化吗？**

**是的，RTL是一种简化，并且做出了不同的架构选择：**

1.  **固定分配而非可重配置bank**：论文使用一个由25个相同bank组成的池，这些bank可以在编译时在ifmap和psum之间动态分区。RTL有4个专用的、硬连线的缓冲区——每种数据类型一个。这在架构上更简单，但灵活性较差。

2.  **滤波器权重在GLB中而非独立存储器中**：论文为滤波器权重提供了独立的存储。RTL将 `filter_glb` 作为4个GLB之一包含在内。

3.  **通过4个BRAM进行位宽打包，而非原生的64位SRAM**：论文的bank原生就是64位宽的。RTL通过将4个16位BRAM组合在一起来实现64位访问，并在端口B上使用地址位操控来读取单个16位值。

4.  **16个 vs 25个物理宏单元**：RTL总共使用16个BRAM，而论文使用25个。论文的总容量（100 KB）是一个固定的硬件参数；RTL的容量可以通过Verilog参数进行配置。

**5. RTL中“可重配置Bank分配”在哪里？**

**在此RTL中不存在。** 没有任何机制可以在运行时或编译时在ifmap和psum之间重新分配存储bank。这四种GLB类型是作为独立的、具有固定角色的模块被实例化的：

```verilog
// glb_unit.sv: 固定的、硬连线的实例
ifmap_glb  #(...) U1_IFMAP (...);
filter_glb #(...) U2_FILTER (...);
bias_glb   #(...) U3_BIAS (...);
psum_glb   #(...) U4_PSUM (...);
```

论文中的可重配置性（例如，为具有大量部分和的层分配更多bank给psum）没有被实现。RTL的方法是针对研究/教育实现的 **静态分区** 设计选择。

**6. GLB深度参数（`shared_pkg.sv`，第182-185行）**

```systemverilog
parameter IFMAP_GLB_DEPTH  = 7945;
parameter FILTER_GLB_DEPTH = 3872;
parameter PSUM_GLB_DEPTH   = 46656;
parameter BIAS_GLB_DEPTH   = 64;
```

这些是以16位条目为单位的 **逻辑深度**。关于每个值的推导，请参见第六季度问题。