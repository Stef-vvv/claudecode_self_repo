# Q4: Filter 64-bit vs Ifmap 16-bit Data Width

## 1. Width Parameters (`shared_pkg.sv`, lines 128-138)

```systemverilog
parameter DATA_WIDTH_IFMAP     = 16;   // ifmap: 16-bit per pixel
parameter ROW_TAG_WIDTH_IFMAP  = 4;
parameter COL_TAG_WIDTH_IFMAP  = 5;

parameter DATA_WIDTH_FILTER    = 64;   // filter: 64-bit per transfer
parameter ROW_TAG_WIDTH_FILTER = 4;
parameter COL_TAG_WIDTH_FILTER = 4;

parameter DATA_WIDTH_PSUM      = 64;   // psum: 64-bit per transfer
parameter ROW_TAG_WIDTH_PSUM   = 4;
parameter COL_TAG_WIDTH_PSUM   = 4;
```

GLB internal data width: `DATA_WIDTH = 16` (all GLBs store 16-bit values).

## 2. How Width Conversion Works

### The `sync_fifo` Width Conversion Mechanism

The `sync_fifo` module (`sync_fifo.v`) supports asymmetric read/write widths via three key parameters:

```verilog
module sync_fifo #(
    parameter R_DATA_WIDTH  = 64,   // read port width
    parameter W_DATA_WIDTH  = 16,   // write port width
    parameter FIFO_DEPTH    = 256
) ...
```

The internal memory uses the **smaller** width: `MEM_WIDTH = min(R_DATA_WIDTH, W_DATA_WIDTH)`. The FIFO stores data at MEM_WIDTH granularity and manages pointer arithmetic accordingly.

**Key sub-modules:**

- **`sync_fifo_mem.v`**: When `R_DATA_WIDTH > W_DATA_WIDTH` (e.g., 64 > 16), writes store 16-bit words at consecutive addresses; reads gather `R_DATA_WIDTH/MEM_WIDTH = 4` consecutive entries and pack them into a 64-bit output:
  ```verilog
  // For read: gather 4 consecutive 16-bit entries into 64-bit
  for (k = 0; k < R_DATA_WIDTH/MEM_WIDTH; k = k + 1) begin : read_mem
      assign rd_data[(k+1)*MEM_WIDTH-1 -: MEM_WIDTH] = (rd_en)? mem[rd_addr + k] : 'b0;
  end
  ```

- **`sync_fifo_wr_ctrl.v`**: Write pointer increments by `W_DATA_WIDTH/MEM_WIDTH` per write (1 when W=MEM, or 4 when W > MEM).

- **`sync_fifo_rd_ctrl.v`**: Read pointer increments by `R_DATA_WIDTH/MEM_WIDTH` per read (1 when R=MEM, or 4 when R > MEM).

- **`sync_fifo_mem.v`**: When `W_DATA_WIDTH > R_DATA_WIDTH`: writes split one wide word across multiple memory locations:
  ```verilog
  for (i = 0; i < W_DATA_WIDTH/MEM_WIDTH; i = i + 1) begin
      mem[wr_addr + i] <= wr_data[(i+1)*MEM_WIDTH-1 -: MEM_WIDTH];
  end
  ```
  Reads return a single narrow word from one memory address.

### `sync_fifo_wrapper.v` — the user-facing wrapper

The wrapper handles the flag generation for asymmetric FIFOs. It adds `sync_fifo_flag_generator` modules that divide the write/read request signals by the width ratio. For instance, when the write side is wider, the write enable fires every N cycles to complete one wide write.

## 3. PE Wrapper: How Ifmap and Filter FIFOs are Instantiated

In `pe_wrapper.v` (lines 87-119), each PE has three input FIFOs:

**Ifmap FIFO: 16-bit in, 16-bit out (symmetric)**
```verilog
sync_fifo #(
    .R_DATA_WIDTH(DATA_WIDTH),           // 16
    .W_DATA_WIDTH(DATA_WIDTH_IFMAP),     // 16
    .FIFO_DEPTH(IFMAP_FIFO_DEPTH)        // 16 (shared_pkg) or 8 (pe_wrapper default)
) ifmap_fifo_inst (...)
```

**Filter FIFO: 64-bit in, 16-bit out (asymmetric, unpacking)**
```verilog
sync_fifo #(
    .R_DATA_WIDTH(DATA_WIDTH),           // 16
    .W_DATA_WIDTH(DATA_WIDTH_FILTER),    // 64
    .FIFO_DEPTH(FILTER_FIFO_DEPTH)       // 16 (shared_pkg) or 8 (pe_wrapper default)
) filter_fifo_inst (...)
```

**Ipsum FIFO: 64-bit in, 16-bit out (asymmetric, unpacking)**
```verilog
sync_fifo #(
    .R_DATA_WIDTH(DATA_WIDTH),           // 16
    .W_DATA_WIDTH(DATA_WIDTH_PSUM),      // 64
    .FIFO_DEPTH(PSUM_FIFO_DEPTH)         // 32 (shared_pkg) or 8 (pe_wrapper default)
) ipsum_fifo_inst (...)
```

**Opsum FIFO: 16-bit in, 64-bit out (asymmetric, packing)**
```verilog
sync_fifo #(
    .R_DATA_WIDTH(DATA_WIDTH_PSUM),      // 64
    .W_DATA_WIDTH(DATA_WIDTH),           // 16
    .FIFO_DEPTH(PSUM_FIFO_DEPTH)         // 32
) opsum_fifo_inst (...)
```

## 4. Data Routing: Complete Trace

### IFMAP Path (16-bit end-to-end)

```
DRAM --> Interface Unit (64-bit FIFO width)
     --> GLB port A: 64-bit write (4 pixels packed into 1 word)
     
GLB stores: 16-bit pixels in 4 parallel dual_bram instances
GLB port B read: 16-bit per access

     --> NoC: ifmap_from_glb = 16-bit (DATA_WIDTH)
     --> noc_wrapper: IFMAP_FIFO_IN_WIDTH=16, IFMAP_FIFO_OUT_WIDTH=16 (symmetric)
     --> GIN: DATA_WIDTH_IFMAP=16
     --> gin_mcc: 16-bit data bus, tag-matched delivery
     --> gin_xbus: 16-bit per column
     --> PE: ifmap input = 16-bit (DATA_WIDTH_IFMAP=16)
     --> PE ifmap_fifo: 16-bit in, 16-bit out
     --> PE ifmap_spad: 16-bit entries
```

### FILTER Path (16-bit GLB -> 64-bit NoC/GIN -> 16-bit PE spad)

```
DRAM --> Interface Unit (64-bit FIFO width)
     --> GLB port A: 64-bit write (4 filter weights packed into 1 word)

GLB stores: 16-bit weights in 4 parallel dual_bram instances
GLB port B read: 16-bit per access (filter_rdata_from_glb_to_noc = 16-bit)

     --> NoC: filter_din = 16-bit (FILTER_FIFO_IN_WIDTH=16)
     --> filter_noc_controller (noc_controller.sv):
         sync_fifo #(
             .R_DATA_WIDTH(64),   // FILTER_FIFO_OUT_WIDTH
             .W_DATA_WIDTH(16),   // FILTER_FIFO_IN_WIDTH
             .FIFO_DEPTH(16)
         ) filter_fifo_inst (...)
         // 4 consecutive 16-bit GLB reads packed into one 64-bit word

     --> GIN: DATA_WIDTH_FILTER=64
     --> gin_mcc: 64-bit data bus
     --> gin_xbus: 64-bit per column
     --> PE: filter input = 64-bit (DATA_WIDTH_FILTER=64)
     --> PE filter_fifo: 64-bit in, 16-bit out (unpacking: 4 writes to 1 read)
     --> PE filter_spad: 16-bit entries (stores p*q*S = p*1*S filter weights)
```

### PSUM Path (similar 16<->64-bit conversion)

```
PE produces: 16-bit psum pixels
     --> PE opsum_fifo: 16-bit in, 64-bit out (packing: 4 psums -> 1 word)
     --> GON: 64-bit bus (DATA_WIDTH_PSUM=64)
     --> NoC opsum: 64-bit
     --> GLB port A: 64-bit write or 16-bit read
     
GLB port B read: 16-bit
     --> NoC: ipsum_din = 16-bit (PSUM_FIFO_IN_WIDTH=16)
     --> ipsum_noc_controller: sync_fifo with 16->64 packing
     --> GIN: 64-bit (DATA_WIDTH_PSUM=64)
     --> PE ipsum_fifo: 64-bit in, 16-bit out (unpacking)
```

## 5. Why 64-bit for Filter? The Math

The filter NoC uses 64-bit because **p filter weights are packed into each transfer**:

- `p = 16` (filters per PE in CONV1)
- Each filter weight = 16-bit (Q0.8 fixed-point)
- 4 filter weights x 16-bit = **64-bit per NoC transfer**

The packing ratio: **4 filter weights per 64-bit word**. This matches the GLB port A width (64-bit) and allows efficient transport through the NoC.

The PE then unpacks each 64-bit word back into 4 x 16-bit filter weights stored in the `filter_spad`.

**Why this is efficient:**
- The NoC has a fixed bus width per data type
- Packing 4 weights into 1 transfer reduces the number of NoC transactions by 4x
- The filter weights for p consecutive filters (same row/col position) are naturally accessed together
- The `filter_spad` depth of 224 can hold `p * q * S = 16 * 1 * 11 = 176` weights for CONV1

## 6. PE filter_spad: 16-bit Internal Storage

Despite receiving 64-bit from the NoC, the PE's `filter_spad` (`pe_filter_spad.v`) only stores **16-bit values**:

```verilog
parameter DATA_WIDTH = 16,
parameter MEM_DEPTH  = 224,
...
reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];  // 224 entries of 16-bit each
```

The 64-bit to 16-bit unpacking happens in the PE's `filter_fifo_inst` (sync_fifo with W_DATA_WIDTH=64, R_DATA_WIDTH=16). The `filter_spad` itself only sees 16-bit wide data and stores individual 16-bit filter weights. It provides one 16-bit weight to the multiplier per cycle.

The 64-bit width is purely a **transport optimization** in the NoC, not a storage format.









































**第四季度问题：滤波器64位 vs Ifmap 16位数据宽度**

**1. 宽度参数（`shared_pkg.sv`，第128-138行）**

```systemverilog
parameter DATA_WIDTH_IFMAP     = 16;   // ifmap：每个像素16位
parameter ROW_TAG_WIDTH_IFMAP  = 4;
parameter COL_TAG_WIDTH_IFMAP  = 5;

parameter DATA_WIDTH_FILTER    = 64;   // 滤波器：每次传输64位
parameter ROW_TAG_WIDTH_FILTER = 4;
parameter COL_TAG_WIDTH_FILTER = 4;

parameter DATA_WIDTH_PSUM      = 64;   // psum：每次传输64位
parameter ROW_TAG_WIDTH_PSUM   = 4;
parameter COL_TAG_WIDTH_PSUM   = 4;
```

GLB内部数据宽度：`DATA_WIDTH = 16`（所有GLB存储16位值）。

**2. 位宽转换如何工作**

**`sync_fifo` 位宽转换机制**

`sync_fifo` 模块（`sync_fifo.v`）通过三个关键参数支持非对称读写宽度：

```verilog
module sync_fifo #(
    parameter R_DATA_WIDTH  = 64,   // 读端口宽度
    parameter W_DATA_WIDTH  = 16,   // 写端口宽度
    parameter FIFO_DEPTH    = 256
) ...
```

内部存储器使用 **较小** 的宽度：`MEM_WIDTH = min(R_DATA_WIDTH, W_DATA_WIDTH)`。FIFO以MEM_WIDTH的粒度存储数据，并相应地管理指针算术。

**关键子模块：**

-   **`sync_fifo_mem.v`**：当 `R_DATA_WIDTH > W_DATA_WIDTH`（例如 64 > 16）时，写入将16位字存储在连续地址中；读取将 `R_DATA_WIDTH/MEM_WIDTH = 4` 个连续条目收集起来，并将它们打包成一个64位输出：
```verilog
// 读：将4个连续的16位条目收集成64位
for (k = 0; k < R_DATA_WIDTH/MEM_WIDTH; k = k + 1) begin : read_mem
    assign rd_data[(k+1)*MEM_WIDTH-1 -: MEM_WIDTH] = (rd_en)? mem[rd_addr + k] : 'b0;
end
```

-   **`sync_fifo_wr_ctrl.v`**：写指针每次写递增 `W_DATA_WIDTH/MEM_WIDTH`（当W=MEM时为1，当W > MEM时为4）。

-   **`sync_fifo_rd_ctrl.v`**：读指针每次读递增 `R_DATA_WIDTH/MEM_WIDTH`（当R=MEM时为1，当R > MEM时为4）。

-   **`sync_fifo_mem.v`**：当 `W_DATA_WIDTH > R_DATA_WIDTH` 时：写入将一个宽字拆分到多个存储器位置中：
```verilog
for (i = 0; i < W_DATA_WIDTH/MEM_WIDTH; i = i + 1) begin
    mem[wr_addr + i] <= wr_data[(i+1)*MEM_WIDTH-1 -: MEM_WIDTH];
end
```
读出从单个存储器地址返回一个窄字。

**`sync_fifo_wrapper.v` — 面向用户的封装**

该封装器处理非对称FIFO的标志生成。它添加了 `sync_fifo_flag_generator` 模块，这些模块将写/读请求信号除以宽度比。例如，当写侧较宽时，写使能每隔N个周期触发一次，以完成一次宽写。

**3. PE封装器：Ifmap和滤波器FIFO是如何被例化的**

在 `pe_wrapper.v`（第87-119行）中，每个PE有三个输入FIFO：

**Ifmap FIFO：16位进，16位出（对称）**
```verilog
sync_fifo #(
    .R_DATA_WIDTH(DATA_WIDTH),           // 16
    .W_DATA_WIDTH(DATA_WIDTH_IFMAP),     // 16
    .FIFO_DEPTH(IFMAP_FIFO_DEPTH)        // 16（shared_pkg）或 8（pe_wrapper默认）
) ifmap_fifo_inst (...)
```

**滤波器FIFO：64位进，16位出（非对称，解包）**
```verilog
sync_fifo #(
    .R_DATA_WIDTH(DATA_WIDTH),           // 16
    .W_DATA_WIDTH(DATA_WIDTH_FILTER),    // 64
    .FIFO_DEPTH(FILTER_FIFO_DEPTH)       // 16（shared_pkg）或 8（pe_wrapper默认）
) filter_fifo_inst (...)
```

**Ipsum FIFO：64位进，16位出（非对称，解包）**
```verilog
sync_fifo #(
    .R_DATA_WIDTH(DATA_WIDTH),           // 16
    .W_DATA_WIDTH(DATA_WIDTH_PSUM),      // 64
    .FIFO_DEPTH(PSUM_FIFO_DEPTH)         // 32（shared_pkg）或 8（pe_wrapper默认）
) ipsum_fifo_inst (...)
```

**Opsum FIFO：16位进，64位出（非对称，打包）**
```verilog
sync_fifo #(
    .R_DATA_WIDTH(DATA_WIDTH_PSUM),      // 64
    .W_DATA_WIDTH(DATA_WIDTH),           // 16
    .FIFO_DEPTH(PSUM_FIFO_DEPTH)         // 32
) opsum_fifo_inst (...)
```

**4. 数据路由：完整追踪**

**IFMAP 路径（端到端16位）**

```
DRAM --> 接口单元（64位 FIFO 宽度）
     --> GLB 端口 A：64位写（4个像素打包成1个字）

GLB 存储：16位像素存储在4个并行的 dual_bram 实例中
GLB 端口 B 读：每次访问16位

     --> NoC：ifmap_from_glb = 16位（DATA_WIDTH）
     --> noc_wrapper：IFMAP_FIFO_IN_WIDTH=16，IFMAP_FIFO_OUT_WIDTH=16（对称）
     --> GIN：DATA_WIDTH_IFMAP=16
     --> gin_mcc：16位数据总线，标签匹配传递
     --> gin_xbus：每列16位
     --> PE：ifmap 输入 = 16位（DATA_WIDTH_IFMAP=16）
     --> PE ifmap_fifo：16位进，16位出
     --> PE ifmap_spad：16位条目
```

**滤波器 路径（16位 GLB -> 64位 NoC/GIN -> 16位 PE spad）**

```
DRAM --> 接口单元（64位 FIFO 宽度）
     --> GLB 端口 A：64位写（4个滤波器权重打包成1个字）

GLB 存储：16位权重存储在4个并行的 dual_bram 实例中
GLB 端口 B 读：每次访问16位（filter_rdata_from_glb_to_noc = 16位）

     --> NoC：filter_din = 16位（FILTER_FIFO_IN_WIDTH=16）
     --> filter_noc_controller（noc_controller.sv）：
         sync_fifo #(
             .R_DATA_WIDTH(64),   // FILTER_FIFO_OUT_WIDTH
             .W_DATA_WIDTH(16),   // FILTER_FIFO_IN_WIDTH
             .FIFO_DEPTH(16)
         ) filter_fifo_inst (...)
         // 4个连续的16位 GLB 读打包成一个64位字

     --> GIN：DATA_WIDTH_FILTER=64
     --> gin_mcc：64位数据总线
     --> gin_xbus：每列64位
     --> PE：滤波器输入 = 64位（DATA_WIDTH_FILTER=64）
     --> PE filter_fifo：64位进，16位出（解包：4次写对应1次读）
     --> PE filter_spad：16位条目（存储 p*q*S = p*1*S 个滤波器权重）
```

**PSUM 路径（类似的16<->64位转换）**

```
PE 产生：16位 psum 像素
     --> PE opsum_fifo：16位进，64位出（打包：4个psum -> 1个字）
     --> GON：64位总线（DATA_WIDTH_PSUM=64）
     --> NoC opsum：64位
     --> GLB 端口 A：64位写或16位读
     
GLB 端口 B 读：16位
     --> NoC：ipsum_din = 16位（PSUM_FIFO_IN_WIDTH=16）
     --> ipsum_noc_controller：sync_fifo 进行 16->64 打包
     --> GIN：64位（DATA_WIDTH_PSUM=64）
     --> PE ipsum_fifo：64位进，16位出（解包）
```

**5. 为什么滤波器用64位？数学上的原因**

滤波器NoC使用64位，是因为 **p 个滤波器权重被打包到每次传输中**：

-   `p = 16`（CONV1中每个PE的滤波器数）
-   每个滤波器权重 = 16位（Q0.8 定点数）
-   4个滤波器权重 x 16位 = **每次NoC传输 64位**

打包比率：**每个64位字包含4个滤波器权重**。这与GLB端口A的宽度（64位）相匹配，并允许通过NoC进行高效传输。

然后，PE将每个64位字解包回4个16位滤波器权重，存储在 `filter_spad` 中。

**为什么这是高效的：**
-   NoC为每种数据类型使用固定的总线宽度
-   将4个权重打包到1次传输中，将NoC事务数量减少了4倍
-   用于p个连续滤波器（相同行/列位置）的滤波器权重天然地一起访问
-   对于CONV1，`filter_spad` 深度为224，可以容纳 `p * q * S = 16 * 1 * 11 = 176` 个权重

**6. PE filter_spad：16位内部存储**

尽管从NoC接收64位数据，PE的 `filter_spad`（`pe_filter_spad.v`）仅存储 **16位值**：

```verilog
parameter DATA_WIDTH = 16,
parameter MEM_DEPTH  = 224,
...
reg [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];  // 224个条目，每个16位
```

64位到16位的解包发生在PE的 `filter_fifo_inst`（sync_fifo 配置为 W_DATA_WIDTH=64，R_DATA_WIDTH=16）中。`filter_spad` 本身只看到16位宽的数据，并存储单个的16位滤波器权重。它每个周期向乘法器提供一个16位权重。

64位宽度纯粹是NoC中的 **传输优化**，而不是存储格式。