"""WriteRam - 将聚合结果写回BRAM (全精度, 硬件在RTL层做Q8量化)"""
class WriteRam:
    def __init__(self, output_bram, pe_cluster, aggregator):
        self.output_bram = output_bram
        self.pe_cluster = pe_cluster
        self.aggregator = aggregator
        self.finished = 0

    def process(self):
        self.finished = 0
        if self.aggregator.finished:
            self.output_bram.write(
                self.aggregator.output_address,
                self.aggregator.output,
                128
            )
            self.finished = 1
