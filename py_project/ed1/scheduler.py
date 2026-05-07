"""
Scheduler - 地址生成与数据分发 (匹配原工程代码风格, 修复bug)

功能: 遍历输入通道/输出通道/空间位置, 在正确时钟周期将数据广播到PE阵列.
原工程bug修复:
  1. filter_port长度从5→3 (PE只用3个滤波器值)
  2. data_port长度从8→5 (PE只用5个数据值)
  3. new_in_data时序修正: 仅在数据有效周期置1, 之后清零
"""

from pe_array import PEArray

class Scheduler:
    def __init__(self, input_bram, filter_bram):
        self.input_bram = input_bram
        self.filter_bram = filter_bram
        self.aggregator = None
        self.write_ram = None

        # 6个PE阵列的数据端口 (每个处理一行输出的3个像素段)
        self.data_port1 = [0] * 5
        self.data_port2 = [0] * 5
        self.data_port3 = [0] * 5
        self.data_port4 = [0] * 5
        self.data_port5 = [0] * 5
        self.data_port6 = [0] * 5

        # 滤波器总线 (广播到所有阵列的第0列)
        self.filter_port = [0] * 3

        # 创建6个PE阵列 (每个处理输出行的一段)
        self.pe_cluster = [
            PEArray(3, self.data_port1, self.filter_port),
            PEArray(3, self.data_port2, self.filter_port),
            PEArray(3, self.data_port3, self.filter_port),
            PEArray(3, self.data_port4, self.filter_port),
            PEArray(3, self.data_port5, self.filter_port),
            PEArray(3, self.data_port6, self.filter_port),
        ]

    def process_step(self):
        """一个时钟周期: 所有PE阵列 + 聚合器 + 写回"""
        for pe_array in self.pe_cluster:
            pe_array.process()
        if self.aggregator:
            self.aggregator.process()
        if self.write_ram:
            self.write_ram.process()

    def run(self):
        """顶层调度循环 - 遍历input_channel, output_channel, 空间tile"""
        num_layers = 32       # 输入通道
        num_rows = 20         # 含padding的行数
        num_filters = 64      # 输出通道

        for input_layer in range(num_layers):
            for skip_row in range(0, num_rows - 4, 3):
                # 每个新的tile: 清除所有PE的new_in_data残留
                for pe_array in self.pe_cluster:
                    for j in range(3):
                        for i in range(3):
                            pe_array.grid[j][i].new_in_data[0] = 0

                # 设置数据有效的PE范围 (除PE(2,2)外全部有效)
                for pe_array in self.pe_cluster:
                    for i in range(3):
                        for j in range(3):
                            pe_array.grid[j][i].new_in_data[0] = 1
                            if i == 2 and j == 2:
                                pe_array.grid[j][i].new_in_data[0] = 0
                new = 1

                for out_f in range(num_filters):
                    # 每个输出通道: 给PE(0,0)发送start脉冲
                    for pe_array in self.pe_cluster:
                        pe_array.grid[0][0].start[0] = 1

                    for count, row in enumerate(range(skip_row, skip_row + 5)):
                        # 更新数据总线 (仅第一个输出通道需要, 数据跨filter复用)
                        if out_f == 0:
                            if row == 0 or row >= 17:
                                ifs_row = [0.0] * 18
                            else:
                                read_address = input_layer * 16 + row - 1
                                ifs_row = [0.0] + self.input_bram.read(read_address, 128) + [0.0]

                            self.data_port1[:] = ifs_row[0:5]
                            self.data_port2[:] = ifs_row[3:8]
                            self.data_port3[:] = ifs_row[6:11]
                            self.data_port4[:] = ifs_row[9:14]
                            self.data_port5[:] = ifs_row[12:17]
                            self.data_port6[:] = ifs_row[13:18]

                        # 更新滤波器总线 (前3拍)
                        if count < 3:
                            filter_address = out_f * 32 * 3 + input_layer * 3 + count
                            self.filter_port[:] = self.filter_bram.read(filter_address, 32)[:3]

                        # 执行时钟周期 (前4拍)
                        if count < 4:
                            self.process_step()

                        # 输出地址入队 (count 1,2,3)
                        if 1 <= count < 4:
                            out_address = out_f * 16 + row - 1
                            self.aggregator.address_queue.append(out_address)

                        # 确保PE(2,2)在正确时刻获得new_in_data
                        if new:
                            new = 0
                            for pe_array in self.pe_cluster:
                                pe_array.grid[2][2].new_in_data[0] = 1

        # 排空流水线
        for i in range(100):
            self.process_step()
