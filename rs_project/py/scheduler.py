"""
Scheduler - RS数据流调度器 (6个PE阵列, 匹配原工程架构)

遍历: input_channel x tile_row x output_channel
6个PE阵列并行处理一行输出的不同像素段:
  Array 0: ifmap cols 0..4  -> 输出像素 0,1,2
  Array 1: ifmap cols 3..7  -> 输出像素 3,4,5
  Array 2: ifmap cols 6..10 -> 输出像素 6,7,8
  Array 3: ifmap cols 9..13 -> 输出像素 9,10,11
  Array 4: ifmap cols 12..16 -> 输出像素 12,13,14
  Array 5: ifmap cols 13..17 -> 输出像素 13,14,15 (只用第3个)

与原工程的关键修正:
  1. filter_port: [0]*5 -> [0]*3
  2. data_port: [0]*8 -> [0]*5
  3. 所有PE在每个tile开始前清除残留start/new_in_data
"""

from pe_array import PEArray

class Scheduler:
    def __init__(self, input_bram, filter_bram):
        self.input_bram = input_bram
        self.filter_bram = filter_bram
        self.aggregator = None
        self.write_ram = None

        # 6个数据总线 (每个PE阵列一段)
        self.data_port1 = [0.0] * 5
        self.data_port2 = [0.0] * 5
        self.data_port3 = [0.0] * 5
        self.data_port4 = [0.0] * 5
        self.data_port5 = [0.0] * 5
        self.data_port6 = [0.0] * 5

        # 共享滤波器总线
        self.filter_port = [0.0] * 3

        # 6个3x3 PE阵列
        self.pe_cluster = [
            PEArray(3, self.data_port1, self.filter_port),
            PEArray(3, self.data_port2, self.filter_port),
            PEArray(3, self.data_port3, self.filter_port),
            PEArray(3, self.data_port4, self.filter_port),
            PEArray(3, self.data_port5, self.filter_port),
            PEArray(3, self.data_port6, self.filter_port),
        ]

        self.all_data_ports = [
            self.data_port1, self.data_port2, self.data_port3,
            self.data_port4, self.data_port5, self.data_port6
        ]

    def process_step(self):
        for pe_array in self.pe_cluster:
            pe_array.process()
        if self.aggregator:
            self.aggregator.process()
        if self.write_ram:
            self.write_ram.process()

    def _reset_all_pe_inputs(self):
        """清除所有PE的残留输入信号."""
        for arr in self.pe_cluster:
            for j in range(3):
                for i in range(3):
                    arr.grid[j][i].start[0] = 0
                    arr.grid[j][i].new_in_data[0] = 0

    def run(self):
        num_layers = 32
        num_rows = 20       # 16 + padding top/bottom
        num_filters = 64

        for input_layer in range(num_layers):
            for skip_row in range(0, num_rows - 4, 3):  # 0,3,6,9,12,15
                # 每个新tile: 所有PE (除PE(2,2)外) 准备锁存新数据
                for arr in self.pe_cluster:
                    for j in range(3):
                        for i in range(3):
                            arr.grid[j][i].new_in_data[0] = 1
                            if i == 2 and j == 2:
                                arr.grid[j][i].new_in_data[0] = 0
                # PE(2,2)在count=0之后获得new_in_data
                new = 1

                for out_f in range(num_filters):
                    # 给每个阵列的PE(0,0)发start脉冲
                    for arr in self.pe_cluster:
                        arr.grid[0][0].start[0] = 1

                    for count, row in enumerate(range(skip_row, skip_row + 5)):
                        # 更新数据总线 (仅out_f==0, 数据跨filter复用)
                        if out_f == 0:
                            read_address = input_layer * 16 + row - 1
                            if row == 0 or row >= 17:
                                ifs_row = [0.0] * 18
                            else:
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

                        # 输出地址入队
                        if 1 <= count < 4:
                            out_address = out_f * 16 + row - 1
                            if self.aggregator:
                                self.aggregator.address_queue.append(out_address)

                        # PE(2,2)在第一个count后获得new_in_data
                        if new and count == 0:
                            new = 0
                            for arr in self.pe_cluster:
                                arr.grid[2][2].new_in_data[0] = 1

                    # 每个filter处理完, 清除残留start
                    for arr in self.pe_cluster:
                        arr.grid[0][0].start[0] = 0

        # 排空流水线
        for i in range(100):
            self.process_step()
