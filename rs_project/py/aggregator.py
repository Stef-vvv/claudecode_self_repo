"""Aggregator - 输出聚合, 将6个PE阵列的3像素输出拼接为16像素行 (匹配原工程)"""
class Aggregator:
    def __init__(self, output_bram, pe_cluster):
        self.output_bram = output_bram
        self.pe_cluster = pe_cluster
        self.address_queue = []
        self.finished = 0
        self.output = [0.0] * 16
        self.output_address = 0

    def process(self):
        self.finished = 0
        # 当第一个阵列完成时触发聚合
        if self.pe_cluster[0].finished:
            if self.address_queue:
                current_address = self.address_queue.pop(0)
                self.output = self.output_bram.read(current_address, 128)

                for i in range(len(self.pe_cluster)):
                    if self.pe_cluster[i].finished:
                        if i == len(self.pe_cluster) - 1:
                            # 最后一个阵列只取第3个输出像素
                            self.output[i*3] += self.pe_cluster[i].output[2]
                        else:
                            for j in range(3):
                                self.output[i*3 + j] += self.pe_cluster[i].output[j]

                self.finished = 1
                self.output_address = current_address
