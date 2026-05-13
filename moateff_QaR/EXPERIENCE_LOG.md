# Eyeriss v1 全系统仿真Debug经验总结

## 日期: 2026-05-12

---

## 一、仿真环境搭建

### 编译
- Vivado 2020.2 xvlog: 71 RTL + 8 Package = 零语法错误
- xelab elaboration: 大量bit-width mismatch warning（接口单元），不影响功能
- pe_array.sv有3个静态数组越界warning（索引-1和12），设计如此

### 仿真速度
- 168 PE阵列 + negedge/posedge双沿 = xsim极慢
- 3644-bit扫描链加载 = 36.45μs仿真 ≈ 20秒墙钟
- 300周期监控 ≈ 1分钟墙钟

### 层次化路径
成功: DUT.SCHEDULER.state_crnt, PassCtrl.state_crnt, ifmap_noc.done/addr/row_tag/col_tag/we_to_gin_fifo/gin_fifo_full/re_from_glb, GLB.U1_IFMAP.U0_0.mem[]
失败: ifmap_noc.state_crnt（无此信号）, index_generator_inst.state_crnt（typedef enum不可访问）, opsum_noc.we_to_gin_fifo（方向不同）

---

## 二、关键架构发现

### 1. 时钟: negedge为主(88%), Scheduler用posedge（有意设计）
### 2. Scheduler需要start_pass（外部从未实现）
### 3. NoC done仅依赖opsum_done（忽略其他3路）
### 4. GLB = 4固定实例 ≠ 论文25可重构bank
### 5. Filter 64-bit NoC传输（4×16打包减少4倍传输）
### 6. 扫描链参数misalignment导致错误参数

---

## 三、死锁根因（已确认）

### 证据链
1. **v4仿真**（参数dump）: 扫描链后参数为全0, 10周期后部分出现但e/p/q/r/t错误
   - 正确: H=8,W=8,R=3,S=3,E=6,F=6,C=1,M=1,N=1,U=1,m=1,n=1
   - 错误: e=24,p=4,q=5,r=0,t=6 (应为6,1,1,1,1)
2. **v6仿真**（force修正参数后）: NoC仍然在~50周期后停止
3. **根因**: 参数misalignment → PE使能位也全错 → 无PE激活 → 数据无人消费

### 配置生成问题
- `config_script.py` 的参数位序与 `scan_chain.sv` 的读取顺序不匹配
- 这导致17个参数的位段偏移 → 参数错乱 → PE配置也全错
- 生成tiny_config需要: 参数位序 100%匹配 scan_chain.sv 的顺序

---

## 四、下一步行动计划

### 立即: 修复配置生成
1. 对比 `config_script.py` 的register order vs `scan_chain.sv` 的scan_ff顺序
2. 确认参数位序完全匹配后重新生成tiny_config
3. 用v4方法dump参数验证

### 之后: 端到端验证
4. 参数正确后用v2/v3框架跑完整pass
5. 对比硬件ofmap vs Python Golden Reference (193,600值)

### 长期: 论文文档
6. moateff_thought重写（信号级模块详解）
7. 01_AUTHOR_EVOLUTION验证（C模型/PE/NoC独立仿真）
