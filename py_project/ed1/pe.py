"""
PE - Processing Element (行为级模型, 匹配原工程代码风格)

每个 PE 完成 5 输入 × 3 滤波器的滑动窗口 MAC 计算.
状态机: IDLE(0) -> MAC(1)[3拍] -> ACC(2)[1拍] -> DONE(3)[1拍] -> IDLE

输入信号:
  start:       启动脉冲 (1拍有效)
  new_in_data: 数据有效使能, 控制是否锁存新数据
  in_data[5]:  广播数据总线 (5个输入像素)
  in_filter[3]: 滤波器总线 (3个权重)
  in_result[3]: 来自上方PE的部分和

输出信号:
  out_result[3]:  输出部分和
  out_filter[3]:  滤波器直通 (向右传递)
  out_start:      启动传播信号 (向右/下)
  finished:       计算完成标志
"""

class PE:
    def __init__(self, window_size=3):
        # 输入端口 (每个 process_one 前由外部设置)
        self.start = [0]
        self.new_in_data = [0]
        self.in_data = [0, 0, 0, 0, 0]
        self.in_filter = [0, 0, 0]
        self.in_result = [0, 0, 0, 0, 0]   # 原作者用长度为5, 实际只用前3

        # 输出端口
        self.out_result = [0, 0, 0]        # 对齐: 也用3
        self.out_filter = [0] * 3           # 对齐: 也用3  (原工程不输出out_result/output_filter, 这里保留命名一致性)
        self.out_start = [0]
        self.finished = 0

        # 内部寄存器
        self.state = 0          # 0=IDLE, 1=MAC, 2=ACC, 3=DONE
        self.iteration = 0
        self.data = [0] * 5     # 锁存的数据寄存器
        self.filter = [0] * 3   # 锁存的滤波器寄存器
        self.result = [0] * 3   # 计算结果寄存器
        self.sliding_window = [0] * window_size

    def process_one(self):
        """
        一个时钟周期. 原工程逻辑: start=1 的同一拍完成数据锁存和第一个MAC.
        这是有意设计, 在硬件中等于组合逻辑路径: 输入->锁存->点积->结果寄存器.
        """

        # ---- 启动检测与数据锁存 ----
        if self.start[0]:
            self.finished = 0
            self.state = 1

            if self.new_in_data[0]:
                self.data = self.in_data.copy()
                self.new_in_data[0] = 0

            self.sliding_window = self.data[:len(self.sliding_window)]
            self.filter = self.in_filter.copy()

            # 清除输入脉冲
            self.start[0] = 0
            self.out_start[0] = 1

        # ---- MAC 计算阶段 (start拍也进入这里, 因为state刚被置为1) ----
        if self.state == 1:
            # 点积: sliding_window[0:3] . filter[0:3]
            self.result[self.iteration] = sum(
                self.sliding_window[i] * self.filter[i] for i in range(3)
            )
            self.iteration += 1

            # 控制信号时序
            if self.iteration == 2:
                self.out_start[0] = 0
            if self.iteration == 3:
                self.state = 2      # -> ACC
                self.iteration = 0
            else:
                # 滑动窗口右移一位
                self.sliding_window = self.sliding_window[1:] + [self.data[self.iteration + 2]]

        # ---- 累加阶段 ----
        elif self.state == 2:
            self.result = [x + y for x, y in zip(self.in_result[:3], self.result)]
            self.finished = 1
            self.state = 3          # -> DONE

        # ---- 完成/复位阶段 ----
        elif self.state == 3:
            self.finished = 0
            self.state = 0          # -> IDLE
