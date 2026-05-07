"""
Top - 顶层集成 (匹配原工程代码风格)

加载conv2数据 → BRAM → Scheduler(6个PE阵列) → Aggregator → WriteRam → 输出文件
"""
from bram import BRAM
from scheduler import Scheduler
from aggregator import Aggregator
from write_to_ram import WriteRam


class Top:
    def __init__(self):
        self.input_bram = BRAM(16 * 16 * 32 * 8 * 100)
        self.filter_bram = BRAM(18432 * 8)
        self.output_bram = BRAM(18432 * 8)

        self.scheduler = Scheduler(self.input_bram, self.filter_bram)
        self.aggregator = Aggregator(self.output_bram, self.scheduler.pe_cluster)
        self.write_ram = WriteRam(self.output_bram, self.scheduler.pe_cluster, self.aggregator)
        self.scheduler.aggregator = self.aggregator
        self.scheduler.write_ram = self.write_ram

    def load_bram(self, file_path, bram, row_length, access_width=128, padding=0):
        """从文件加载数据到BRAM (逐行, row_length个值一行)."""
        addr = 0
        with open(file_path, "r") as f:
            data = [float(line.strip()) for line in f.readlines()]

        offset = 0
        total_elements = len(data)

        while offset < total_elements:
            row_data = data[offset:offset + row_length]
            if len(row_data) < row_length:
                row_data += [0.0] * (row_length - len(row_data))
            row_data += [0.0] * padding

            bram.write(addr, row_data, access_width)
            offset += row_length
            addr += 1

    def store_bram_to_file(self, bram, out_file, total_elements):
        """从BRAM读取数据并写入文件 (每行一个值)."""
        with open(out_file, "w") as f:
            for addr in range(total_elements):
                value = bram.mem[addr]
                f.write(f"{value}\n")

    def initialize(self):
        self.load_bram(
            "conv2.input.real.dat",
            self.input_bram,
            row_length=16,
            access_width=128,
            padding=0,
        )
        self.load_bram(
            "conv2.real.dat",
            self.filter_bram,
            row_length=3,
            access_width=32,
            padding=1,
        )

    def run(self):
        self.scheduler.run()
        self.store_bram_to_file(
            self.output_bram,
            "ed_run_output.dat",
            total_elements=16384,
        )


def main():
    top = Top()
    top.initialize()
    print("Data loaded. Running scheduler...")
    top.run()
    print("Done. Output saved to ed_run_output.dat")


if __name__ == "__main__":
    main()
