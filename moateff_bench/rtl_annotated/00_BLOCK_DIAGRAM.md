# Eyeriss v1 RS数据流加速器 — 硬件模块框图

## 1. 系统顶层架构

```
                              ┌──────────────────────────────────────┐
                              │           EYERISS (顶层)              │
                              │         eyeriss.sv                   │
                              └──────────────────────────────────────┘
                                                │
        ┌───────────┬───────────┬───────────┬───┴───────────┬───────────┐
        │           │           │           │               │           │
   ┌────▼────┐ ┌───▼────┐ ┌───▼────┐ ┌───▼────┐     ┌────▼────┐ ┌───▼────┐
   │ SCAN    │ │Scheduler│ │Process │ │  GLB   │     │Interface│ │ ReLU   │
   │ CHAIN   │ │(调度器) │ │ Unit   │ │(全局   │     │ Unit    │ │(激活)  │
   │(配置链) │ │         │ │(处理)  │ │ 缓存)  │     │(接口)   │ │        │
   └────┬────┘ └───┬────┘ └───┬────┘ └───┬────┘     └────┬────┘ └───▲────┘
        │          │          │          │               │          │
        │    配置  │   启动   │  读写    │         片外  │    输出  │
        │    参数  │   NoC    │   GLB    │         DRAM  │    数据  │
        │          │          │          │               │          │
        └──────────┴──────────┴──────────┴───────────────┘          │
                                   │                                  │
                                   └──────────────────────────────────┘
```

## 2. 数据流总览

```
                         ┌──────────────┐
    off-chip DRAM ◄─────►│  INTERFACE   │  (异步FIFO, 跨core_clk/link_clk)
                         │  UNIT        │
                         └──────┬───────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
         ┌────▼────┐      ┌────▼────┐      ┌────▼────┐
         │ IFMAP   │      │ FILTER  │      │ PSUM    │  ← GLB (4-bank BRAM)
         │ GLB     │      │ GLB     │      │ GLB     │    深度: 7945/3872/46656
         │ 7945深  │      │ 3872深  │      │ 46656深 │
         └────┬────┘      └────┬────┘      └────┬────┘
              │                │                 │
              │         ┌──────┘                 │
              │         │                        │
         ┌────▼─────────▼────────────────────────▼──────┐
         │              NoC Controller                  │
         │  ┌──────────────────────────────────────┐   │
         │  │ pass_controller (4状态FSM)           │   │
         │  │  IDLE→START→PROCESSING→DONE         │   │
         │  └──────────────────────────────────────┘   │
         │  ┌──────────┐ ┌──────────┐ ┌──────────┐    │
         │  │ ifmap    │ │ filter   │ │ psum     │    │
         │  │ NoC      │ │ NoC      │ │ NoC      │    │
         │  │ Controller│ │ Controller│ │ Controller│   │
         │  │ [idx_gen]│ │ [idx_gen]│ │ [idx_gen]│    │
         │  │ [mapper] │ │ [mapper] │ │ [mapper] │    │
         │  │ [tag_gen]│ │ [tag_gen]│ │ [tag_gen]│    │
         │  └────┬─────┘ └────┬─────┘ └────┬─────┘    │
         └───────┼─────────────┼─────────────┼─────────┘
                 │             │             │
         ┌───────▼─────┐ ┌────▼──────┐ ┌───▼──────────┐
         │  GIN (组播) │ │ GIN (组播)│ │ GIN (组播)    │
         │  [gin.sv]   │ │           │ │               │
         │  Row MCC    │ │ Row MCC   │ │ Row MCC       │
         │  Col XBus   │ │ Col XBus  │ │ Col XBus      │
         └───────┬─────┘ └────┬──────┘ └───┬───────────┘
                 │             │             │
                 └─────────────┼─────────────┘
                               │
                    ┌──────────▼──────────┐
                    │   PE Array (12×14)  │
                    │   pe_array.sv       │
                    │                     │
                    │  Row 0: [PE][PE]... │ ← opsum→GON
                    │    ↑ psum向上流     │
                    │  Row 1: [PE][PE]... │
                    │    ↑               │
                    │  ...                │
                    │  Row11: [PE][PE]... │ ← ipsum←GIN
                    └──────────┬──────────┘
                               │
                    ┌──────────▼──────────┐
                    │  GON (汇聚)         │
                    │  [gon.sv]           │
                    │  Col XBus → Row MCC │
                    └──────────┬──────────┘
                               │
                         ┌─────▼─────┐
                         │   ReLU    │
                         │   (4路)   │
                         └─────┬─────┘
                               │
                         写回 PSUM GLB
```

## 3. PE内部结构

```
                   ┌─────────────────────────────────────────────┐
                   │              PE Wrapper (pe_wrapper.v)       │
                   │                                             │
  ifmap ──────────►│  ┌─────────┐    ┌──────────┐               │
  (16-bit)         │  │ ifmap   │    │  clk_    │               │
  push_ifmap ─────►│  │ FIFO    │───►│  gating  │───► gated_clk │
                   │  │ (16深)  │    └──────────┘               │
                   │  └─────────┘                                │
  filter ─────────►│  ┌─────────┐                                │
  (64-bit)         │  │ filter  │                                │
  push_filter ────►│  │ FIFO    │                                │
                   │  │ (16深)  │                                │
                   │  └─────────┘                                │
  ipsum ──────────►│  ┌─────────┐                                │
  (64-bit)         │  │ ipsum   │                                │
  push_ipsum ─────►│  │ FIFO    │                                │
                   │  │ (32深)  │                                │
                   │  └─────────┘                                │
                   │       │         ┌──────────────────────┐   │
                   │       └─────────┤     PE Core (pe.v)   │   │
                   │                 │                      │   │
                   │    ┌──────────┐ │  ┌────────────────┐  │   │
                   │    │ ifmap    │ │  │ pe_controller  │  │   │
                   │    │ SPAD     │◄├──┤ (6状态FSM)     │  │   │
                   │    │ (12深)   │ │  │ negedge clk    │  │   │
                   │    │ [移位式] │ │  └────────────────┘  │   │
                   │    └────┬─────┘ │                      │   │
                   │         │       │  ┌────────────────┐  │   │
                   │    ┌────▼─────┐ │  │   MAC Pipeline │  │   │
                   │    │ filter   │ │  │                │  │   │
                   │    │ SPAD     │ │  │ ifmap×filter   │  │   │
                   │    │ (224深)  │ │  │   ↓ (32-bit)   │  │   │
                   │    │ [BRAM式] │ │  │ truncator      │  │   │
                   │    └────┬─────┘ │  │   ↓ (16-bit)   │  │   │
                   │         │       │  │ adder←ipsum    │  │   │
                   │         ▼       │  │   ↓            │  │   │
                   │    ┌─────────┐  │  │ psum SPAD      │  │   │
                   │    │ ×(mult) │  │  │ (24深)         │  │   │
                   │    └────┬────┘  │  └────────────────┘  │   │
                   │         │       │                      │   │
                   │    ┌────▼────┐  │   opsum ────────────►│───┤ opsum
                   │    │ trunc   │  │   push_opsum ───────►│   │ (64-bit)
                   │    └────┬────┘  │                      │   │
                   │         │       └──────────────────────┘   │
                   │    ┌────▼────┐                              │
                   │    │  +      │                              │
                   │    │ (adder) │                              │
                   │    └────┬────┘                              │
                   │         │                                   │
                   │    ┌────▼────┐                              │
                   │    │ psum    │                              │
                   │    │ SPAD    │                              │
                   │    │ (24深)  │                              │
                   │    └─────────┘                              │
                   └─────────────────────────────────────────────┘
```

## 4. Scheduler状态机

```
                        ┌─────┐
                        │IDLE │◄────────────────────────────┐
                        └──┬──┘                             │
                           │ start                          │
                           ▼                                │
                        ┌───────┐                           │
                        │ CHECK │◄──────────────┐           │
                        └───┬───┘                │           │
                            │ start_pass         │           │
                            ▼                    │           │
                        ┌────────────┐           │           │
                        │ START_PASS │           │           │
                        │ (start_noc)│           │           │
                        └─────┬──────┘           │           │
                              │                  │           │
                              ▼                  │           │
                        ┌─────────┐              │           │
                        │ PROCESS │ (busy=1)     │           │
                        │ 等待    │              │           │
                        │ noc_done│              │           │
                        └────┬────┘              │           │
                             │ noc_done          │           │
                             ▼                   │           │
                        ┌───────────┐            │           │
                        │ PASS_DONE │            │           │
                        └─────┬─────┘            │           │
                              │                  │           │
                              ▼                  │           │
                        ┌─────────────┐          │           │
                        │ INNER_LOOP  │          │           │
                        │ m+=p*t      │          │           │
                        │ C+=q*r      │          │           │
                        └──┬──────┬───┘          │           │
                           │      │              │           │
                    内层未完│      │内层完成      │           │
                      ─────┘      └─────┐        │           │
                                        ▼        │           │
                                  ┌─────────┐    │           │
                                  │ DUMPING │    │           │
                                  │(ofmap_  │    │           │
                                  │ dump=1) │    │           │
                                  └────┬────┘    │           │
                                       │         │           │
                                  dump_done      │           │
                                       ▼         │           │
                                  ┌────────────┐ │           │
                                  │ OUTER_LOOP │ │           │
                                  │ M+=m       │ │           │
                                  │ E+=e       │ │           │
                                  │ N+=n       │ │           │
                                  └──┬─────┬───┘ │           │
                                     │     │     │           │
                              外层未完│     │外层完成         │
                                ─────┘     └────►┌──────┐    │
                                                 │ DONE │────┘
                                                 └──────┘
```

## 5. NoC地址生成流程

```
  Scheduler输出:
  filter_ids, channel_ids, ifmap_ids
              │
              ▼
  ┌────────────────────────────────────────┐
  │         pass_controller                │
  │  IDLE → START_NOCS → PROCESSING → DONE│
  └────────────────────────────────────────┘
              │ (并行启动4路)
    ┌─────────┼─────────┬─────────┐
    ▼         ▼         ▼         ▼
┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐
│ifmap  │ │filter │ │ipsum  │ │opsum  │
│NoC    │ │NoC    │ │NoC    │ │NoC    │
└───┬───┘ └───┬───┘ └───┬───┘ └───┬───┘
    │         │         │         │
    ▼         ▼         ▼         ▼
┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐
│Index  │ │Index  │ │Index  │ │Index  │
│Gen    │ │Gen    │ │Gen    │ │Gen    │
│(5层   │ │(lock- │ │(lock- │ │(lock- │
│ 嵌套) │ │ step) │ │ step) │ │ step) │
└───┬───┘ └───┬───┘ └───┬───┘ └───┬───┘
    │         │         │         │
    ▼         ▼         ▼         ▼
┌───────┐ ┌───────┐ ┌───────┐ ┌───────┐
│Mapper │ │Mapper │ │Mapper │ │Mapper │
│4D→1D  │ │4D→1D  │ │4D→1D  │ │4D→1D  │
└───┬───┘ └───┬───┘ └───┬───┘ └───┬───┘
    │         │         │         │
    ▼         ▼         ▼         ▼
  GLB地址   GLB地址   GLB地址   GLB地址

Mapper公式: addr = idx4*(dim3*dim2*dim1) + idx3*(dim2*dim1) + idx2*dim1 + idx1

┌──────────┬────────┬────────┬────────┬────────┐
│ 数据类型 │  dim4  │  dim3  │  dim2  │  dim1  │
├──────────┼────────┼────────┼────────┼────────┤
│  IFMAP   │   N    │   C    │   H    │   W    │
│  FILTER  │   M    │   C    │   R    │   S    │
│  PSUM    │   N    │   M    │   F    │   E    │
│  BIAS    │   -    │   -    │   -    │   M    │
└──────────┴────────┴────────┴────────┴────────┘
```

## 6. PE Array PSum流动

```
  PE Array (12行×14列) — 仅展示一列的PSum流动:

    Col j
  ┌──────────┐
  │ PE[0][j] │ ← opsum → GON (opsum_ln_sel[0]=1)
  │  (顶部)  │ ← ipsum ← PE[1][j].opsum
  ├──────────┤
  │ PE[1][j] │ ← opsum → PE[0][j].ipsum
  │          │ ← ipsum ← PE[2][j].opsum
  ├──────────┤
  │   ...    │
  ├──────────┤
  │ PE[10][j]│ ← opsum → PE[9][j].ipsum
  │          │ ← ipsum ← PE[11][j].opsum
  ├──────────┤
  │ PE[11][j]│ ← opsum → PE[10][j].ipsum
  │  (底部)  │ ← ipsum ← GIN (ipsum_ln_sel[11]=1)
  └──────────┘

  配置: ipsum_ln_sel[row] = 1 → 从GIN取ipsum (列底)
        ipsum_ln_sel[row] = 0 → 从PE[row+1]取ipsum
        opsum_ln_sel[row] = 1 → 输出到GON (列顶)
        opsum_ln_sel[row] = 0 → 输出到PE[row-1]
```

## 7. 完整模块层次树

```
eyeriss (EYERISS.sv)
│
├── SCAN_CHAIN (scan_chain.sv)
│   └── scan_ff_Nbit × 17 (H,W,R,S,E,F,C,M,N,U,m,n,e,p,q,r,t)
│       └── scan_ff × N
│
├── SCHEDULER (scheduler.sv)
│   └── 9-state FSM + 嵌套循环计数器
│
├── PROCESSING (processing_unit.sv)
│   ├── pe_array (pe_array.sv)
│   │   ├── PE[0..11][0..13] (pe_wrapper.v → pe.v)
│   │   │   ├── clk_gating
│   │   │   ├── sync_fifo × 4 (ifmap/filter/ipsum/opsum)
│   │   │   │   ├── sync_fifo_mem
│   │   │   │   ├── sync_fifo_rd_ctrl
│   │   │   │   ├── sync_fifo_wr_ctrl
│   │   │   │   ├── sync_fifo_up_down_counter
│   │   │   │   └── sync_fifo_flag_generator
│   │   │   └── pe (pe.v)
│   │   │       ├── pe_controller (6-state FSM)
│   │   │       ├── zero_skipping
│   │   │       ├── ifmap_spad (12深, 移位寄存器式)
│   │   │       ├── filter_spad (224深, BRAM式)
│   │   │       ├── psum_spad (24深, BRAM式)
│   │   │       ├── multiplier (16×16→32)
│   │   │       ├── truncator (32→16)
│   │   │       ├── adder
│   │   │       ├── mux2x1 × 3
│   │   │       └── flopr × 3 (流水线寄存器)
│   │   ├── ifmap_gin (gin_wrapper → gin → gin_mcc + gin_xbus)
│   │   ├── filter_gin
│   │   ├── ipsum_gin
│   │   └── opsum_gon (gon_wrapper → gon → gon_mcc + gon_xbus)
│   │
│   └── noc_wrapper
│       ├── pass_controller (4-state FSM)
│       └── noc_controller
│           ├── ifmap_noc_controller
│           │   ├── ifmap_index_generator (5层嵌套)
│           │   ├── mapper (4D→1D)
│           │   ├── ifmap_tag_generator
│           │   └── sync_fifo
│           ├── filter_noc_controller
│           │   ├── filter_index_generator (lock-step)
│           │   ├── mapper
│           │   ├── filter_tag_generator
│           │   └── sync_fifo
│           ├── ipsum_noc_controller
│           │   ├── psum_index_generator (lock-step)
│           │   ├── mapper
│           │   ├── psum_tag_generator
│           │   └── sync_fifo
│           └── opsum_noc_controller
│               ├── psum_index_generator
│               ├── mapper
│               ├── psum_tag_generator
│               └── sync_fifo
│
├── GLB (glb_unit.sv)
│   ├── U1_IFMAP (ifmap_glb.sv)
│   │   └── dual_bram × 4 (1986深/每bank)
│   ├── U2_FILTER (filter_glb.sv)
│   │   └── dual_bram × 4 (968深/每bank)
│   ├── U3_BIAS (bias_glb.sv)
│   │   └── dual_bram × 4 (16深/每bank)
│   └── U4_PSUM (psum_glb.sv)
│       └── dual_bram × 4 (11664深/每bank)
│
├── INTF (interface_unit.sv)
│   ├── reset_sync × 2
│   ├── clk_mux × 2
│   ├── async_fifo
│   │   ├── async_fifo_ctrl (controller FSM)
│   │   ├── async_fifo_mem
│   │   ├── async_fifo_wr_ctrl (wfull)
│   │   ├── async_fifo_rd_ctrl (rempty)
│   │   └── addr_generator
│   ├── mux1/mux2 (muxx/muxxx)
│   └── demux1/demux2 (demuxx/demuxxx)
│
└── ReLU (relu_array.sv)
    └── relu × 4
```
