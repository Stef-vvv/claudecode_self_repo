"""
PE Array - 3x3 脉动阵列 (行为级模型, 匹配原工程代码风格)

简化RS数据流:
  - 数据:  广播到所有9个PE (同一总线)
  - 滤波器: 从列0向右传播
  - 部分和: 从行0向下传播 (仅当上方PE完成时)
  - 启动:   沿对角线传播 (上方out_start 或 左方out_start)

核心简化: 数据广播 + start对角线传播 → 等效3x1垂直累加器
第0列PE完成有效计算, 第1、2列PE执行冗余计算 (模拟2D RS数据流运动).
"""

from pe import PE


class PEArray:
    def __init__(self, n, data_port, filter_port):
        self.n = n
        self.grid = [[PE(3) for _ in range(n)] for _ in range(n)]

        self.finished = 0
        self.output = 0

        # 连接外部端口
        for i in range(n):
            for j in range(n):
                self.grid[j][i].in_data = data_port       # 所有PE共享数据总线
                if i == 0:
                    self.grid[j][i].in_filter = filter_port  # 只有第0列接外部滤波器

    def process(self):
        """一个时钟周期: PE计算 -> PE间通信 -> 输出检测"""
        self.finished = 0

        # ---- Phase 1: 所有 PE 并行执行一个周期 ----
        for j in range(self.n):
            for i in range(self.n):
                self.grid[j][i].process_one()

        # ---- Phase 2: PE 间数据传递 ----
        for j in range(self.n):
            for i in range(self.n):
                # 滤波器: 从左向右传播
                if i != 0:
                    self.grid[j][i].in_filter = self.grid[j][i-1].filter.copy()

                # 部分和: 从上向下传播 (仅在PE完成计算后, 保证数据有效)
                if j != 0:
                    if self.grid[j-1][i].finished:
                        self.grid[j][i].in_result = self.grid[j-1][i].result.copy()

                # 启动信号: 对角线传播 (上方或左方out_start)
                above_start = [1] if j != 0 and self.grid[j-1][i].out_start[0] else [0]
                left_start  = [1] if i != 0 and self.grid[j][i-1].out_start[0] else [0]

                if i != 0 or j != 0:
                    self.grid[j][i].start[0] = 1 if (above_start[0] or left_start[0]) else 0

        # ---- Phase 3: 输出检测 (取最先完成的最底部PE结果) ----
        for i in range(self.n):
            if self.grid[self.n-1][i].finished:
                self.output = self.grid[self.n-1][i].result
                self.finished = 1
                break

    # ---- 调试打印函数 (保留原工程风格) ----
    def print_array_in_data(self):
        for j in range(self.n):
            for i in range(self.n):
                print(self.grid[j][i].in_data, end=" ")
            print()
        print("---------------")

    def print_array_results(self):
        for j in range(self.n):
            for i in range(self.n):
                print(self.grid[j][i].result, end=" ")
            print()
        print("---------------")

    def print_array_start(self):
        for j in range(self.n):
            for i in range(self.n):
                print(self.grid[j][i].new_in_data, end=" ")
            print()
        print("---------------")

    def print_array_filter(self):
        for j in range(self.n):
            for i in range(self.n):
                print(self.grid[j][i].filter, end=" ")
            print()
        print("---------------")
